#!/bin/bash

echo "Waiting for Suricata socket at ${SURICATA_UNIX_SOCKET}"

# Wait up to 120 seconds for the socket to be created
MAX_WAIT=120
COUNTER=0

while [ ! -S "${SURICATA_UNIX_SOCKET}" ]; do
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo "Timeout waiting for Suricata socket after ${MAX_WAIT} seconds"
        exit 1
    fi

    echo "Socket not ready yet, waiting... ($COUNTER/$MAX_WAIT)"
    sleep 5
    COUNTER=$((COUNTER+5))
done

echo "Suricata socket is ready, starting suri_reloader"
# Use our custom suri_reloader that runs in foreground
exec python3 /usr/local/bin/suri_reloader.py