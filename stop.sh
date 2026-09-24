#!/bin/bash
# One-command shutdown for this repo's SearXNG and OpenWebUI.
# Run this from anywhere: /path/to/local_ai_setup/stop.sh

set -euo pipefail

# Always operate from the folder this script lives in, regardless of
# what directory you were in when you ran it.
cd "$(dirname "$0")"

# Linux needs an extra override so Open WebUI can reach Ollama on the host.
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "$OSTYPE" != "darwin"* ]]; then
    COMPOSE_FILES+=(-f docker-compose.linux.yml)
fi

echo "==> Stopping SearXNG and Open WebUI..."
podman-compose "${COMPOSE_FILES[@]}" down

echo "==> Services stopped."