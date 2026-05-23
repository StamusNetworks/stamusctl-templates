#!/bin/sh
set -e

DASHBOARDS_URL="http://opensearch-dashboards:5601"

echo "Creating OpenSearch Dashboards index patterns for application logs..."

# Application logs - combined index pattern
curl -sf -XPOST "${DASHBOARDS_URL}/api/saved_objects/index-pattern/applogs-*" \
  -H "Content-Type: application/json" \
  -H "osd-xsrf: true" \
  -d '{"attributes":{"title":"applogs-*","timeFieldName":"@timestamp"}}' \
  || echo "applogs-* pattern may already exist, skipping"

# Application logs - per-app index patterns
for app in scirius arkime suricata opensearch postgresql nginx scout; do
  curl -sf -XPOST "${DASHBOARDS_URL}/api/saved_objects/index-pattern/applogs-${app}*" \
    -H "Content-Type: application/json" \
    -H "osd-xsrf: true" \
    -d "{\"attributes\":{\"title\":\"applogs-${app}*\",\"timeFieldName\":\"@timestamp\"}}" \
    || echo "applogs-${app}* pattern may already exist, skipping"
done

echo "Dashboards index patterns created."
