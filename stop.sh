#!/bin/bash
# One-command shutdown for this repo's SearXNG stack.
# Run this from anywhere: /path/to/local_ai_setup/stop.sh

set -e

# Always operate from the folder this script lives in, regardless of
# what directory you were in when you ran it.
cd "$(dirname "$0")"

# Podman only needs a VM on macOS; on Linux it runs containers natively.
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "==> Checking Podman machine..."
    if ! podman machine list --format "{{.Running}}" | grep -q "true"; then
        echo "==> Podman machine not running."
    else
        echo "==> Podman machine already running."
    fi
fi

# Linux needs an extra override so Open WebUI can reach Ollama on the host.
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "$OSTYPE" != "darwin"* ]]; then
    COMPOSE_FILES+=(-f docker-compose.linux.yml)
fi

echo "==> Stopping SearXNG and Open WebUI..."
podman-compose "${COMPOSE_FILES[@]}" down

echo "==> Services stopped."