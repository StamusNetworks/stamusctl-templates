#! /bin/sh
# © Charles BLANC-ROLIN - https://pawpatrules.fr
# This script comes with ABSOLUTELY NO WARRANTY!
# License : GPLv3
# This script delete indexes on OpenSearch containter.
# It is intended to be used daily via cron, if data is older than the number of retention days you set, it will not be deleted.

# To enable, uncomment the last line of the script and add this line in OS crontab (not in container) for root user :
# 00 03 * * * sh {PWD}/opensearch-daily-cleanup.sh

# Define number of days (>1) you want to keep :
RETENTION=30

# Specify container name
CONTAINER_NAME=$(docker ps -a | grep -o 'config-scirius-.*')

echo "\n##########################################################\nOpenSearch Daily Cleanup Script for ClearNDR\n##########################################################\n"
echo "You've choosed $RETENTION days of retention\n"

# List indexes
indices=$(docker exec $CONTAINER_NAME curl -s -X GET "http://elasticsearch:9200/_cat/indices?h=index" | grep logstash-*)

# Date -Timestamp
current_date=$(date +%s)

# Parse indexes in indices endpoint
for index in $indices; do
  # Extract date from index name
  index_date=$(echo "$index" | grep -oP '\d{4}.\d{2}.\d{2}')

  if [ -n "$index_date" ]; then
    # Convert to date format
    index_date=$(echo "$index_date" | sed 's/\./-/g')

    # Convert indexe date to timestamp
    index_timestamp=$(date -d "$index_date" +%s)

    # Diff
    age_days=$(( (current_date - index_timestamp) / 86400 ))

    # Compare age with retention defined
    if [ "$age_days" -gt "$RETENTION" ]; then
      echo "\nDeletion fo $index (created at $index_date, age: $age_days days)\n"
      
      # Delete indice
      docker exec $CONTAINER_NAME curl -X DELETE -s -i "http://elasticsearch:9200/$index"
    fi
  fi
done
