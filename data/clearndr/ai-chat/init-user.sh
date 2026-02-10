#!/bin/sh
# Auto-create default LibreChat user on first startup

set -e

# Copy script to /app to access node_modules
cp /create-default-user.js /app/create-default-user.js

cd /app

# Run the custom user creation script
node create-default-user.js
