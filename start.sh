#!/bin/bash
# One-command startup for the SearXNG + Continue setup.
# Run this from anywhere: ~/ai-search/start.sh

set -e

# Always operate from the folder this script lives in, regardless of
# what directory you were in when you ran it.
cd "$(dirname "$0")"

echo "==> Checking Podman machine..."
if ! podman machine list --format "{{.Running}}" | grep -q "true"; then
    echo "==> Starting Podman machine (this can take a few seconds)..."
    podman machine start
else
    echo "==> Podman machine already running."
fi

echo "==> Starting SearXNG..."
podman-compose up -d

echo "==> Starting the Continue bridge server..."
echo "==> Leave this window open. Press Ctrl+C to stop everything when you're done."
python3 searxng_bridge.py
