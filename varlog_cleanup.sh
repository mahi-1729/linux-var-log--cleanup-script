#!/bin/bash
# Set the log retention period and usage threshold
log_retention_days=6
disk_usage_threshold=60

# Get current disk usage percentage of /var/log
disk_usage=$(df /var/log | awk 'NR==2 {print $5}' | sed 's/%//')

# Find and delete old compressed log files (older than retention period) excluding HTTPD and Apache logs
find /var/log -type f -mtime +$log_retention_days \( -name "*.gz" -o -name "*.xz" \) \
    ! -path "/var/log/httpd/*" ! -path "/var/log/apache2/*" ! -path "/var/log/mysql/*" ! -path "/var/log/postgresql/*" ! -path "/var/log/atop/*" ! -path "/var/log/audit/*" \
    -exec echo "Deleting file: {}" \; -exec rm {} \;

# Find the dated files not ending in .gz or .xz and gzip them, excluding HTTPD and Apache logs
find /var/log -type f -name '*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' \
    ! -path "/var/log/httpd/*" ! -path "/var/log/apache2/*" ! -path "/var/log/mysql/*" ! -path "/var/log/postgresql/*" ! -path "/var/log/atop/*" ! -path "/var/log/audit/*" | while read -r file; do
    gzip "$file" && echo "Compressed: $file"
done

# Get current disk usage (in percentage) of /var/log
current_disk_usage=$(df /var/log | awk 'NR==2 {print $5}' | sed 's/%//')

# Only proceed if disk usage is above the threshold
if [ "$current_disk_usage" -gt "$disk_usage_threshold" ]; then
    echo "Disk usage is above threshold ($current_disk_usage%). Proceeding with log compression..."

    # Find all files not ending in .gz or .xz and less than 5 days old, gzip them and truncate
    # excluding HTTPD, Apache, MySQL, PostgreSQL, Atop, and Audit logs
    find /var/log -type f ! -name '*.gz' ! -name '*.xz' -mtime -5 \
        ! -path "/var/log/httpd/*" ! -path "/var/log/apache2/*" ! -path "/var/log/mysql/*" ! -path "/var/log/postgresql/*" \
        ! -path "/var/log/atop/*" ! -path "/var/log/audit/*" | while read -r file; do
        # Compress and truncate each log file
        gzip -c "$file" > "${file}_$(date +%Y%m%d%H).gz" && truncate -s 0 "$file"
    done
else
    echo "Disk usage is below threshold ($current_disk_usage%). No action taken."
fi

# Check if disk usage exceeds the threshold
if [ "$disk_usage" -gt "$disk_usage_threshold" ]; then
    echo "Disk usage is at ${disk_usage}%, exceeding the threshold of ${disk_usage_threshold}%. Performing cleanup..."

    # Remove old uncompressed log files (older than retention period and not .gz or .xz), excluding HTTPD and Apache logs
    find /var/log/ -type f -mtime +$log_retention_days ! \( -name "*.gz" -o -name "*.xz" \) \
        ! -path "/var/log/httpd/*" ! -path "/var/log/apache2/*" ! -path "/var/log/mysql/*" ! -path "/var/log/postgresql/*" ! -path "/var/log/atop/*" ! -path "/var/log/audit/*" \
        -exec echo "Deleting file: {}" \; -exec rm {} \;

    # Reload syslog services
    /bin/systemctl reload rsyslog > /dev/null 2>/dev/null || true
    /bin/systemctl reload syslog-ng > /dev/null 2>/dev/null || true
    /bin/systemctl reload syslog > /dev/null 2>/dev/null || true
fi
