#!/bin/bash
# One-command startup for this repo's SearXNG stack.
# Run this from anywhere: /path/to/local_ai_setup/start.sh

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

echo "==> SearXNG is up at http://localhost:8080"
echo "==> Ollama runs as a background service — open VS Code and use Cline."
