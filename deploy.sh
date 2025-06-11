#!/bin/bash

set -e

# Define paths
NAGIOS_CFG="/usr/local/nagios/etc/nagios.cfg"
NAGIOS_BIN="/usr/local/nagios/bin/nagios"
CONTAINER_NAME="nagios2"

echo "🔄 Reverting local changes..."
git reset --hard HEAD
git clean -fd

echo "📥 Pulling latest files from Git..."
git pull origin main

echo "🔍 Verifying Nagios configuration inside container..."

docker exec "$CONTAINER_NAME" bash -c "$NAGIOS_BIN -v $NAGIOS_CFG"

if [ $? -eq 0 ]; then
    echo "✅ Nagios configuration is OK. Reloading Nagios service..."
    docker exec "$CONTAINER_NAME" service nagios reload
else
    echo "❌ Nagios configuration check failed. Not reloading service."
    exit 1
fi

