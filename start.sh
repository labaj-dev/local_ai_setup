#!/bin/bash
# One-command startup for this repo's SearXNG stack.
# Run this from anywhere: /path/to/local_ai_setup/start.sh

set -euo pipefail

# Always operate from the folder this script lives in, regardless of
# what directory you were in when you ran it.
cd "$(dirname "$0")"

# Podman only needs a VM on macOS; on Linux it runs containers natively.
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "==> Checking Podman machine..."
    if ! podman machine list --format "{{.Running}}" | grep -q "true" 2>/dev/null; then
        echo "==> Starting Podman machine (this can take a few seconds)..."
        podman machine start
    else
        echo "==> Podman machine already running."
    fi
fi

# Linux needs an extra override so Open WebUI can reach Ollama on the host.
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "$OSTYPE" != "darwin"* ]]; then
    COMPOSE_FILES+=(-f docker-compose.linux.yml)
fi

echo "==> Starting SearXNG and Open WebUI..."
podman-compose "${COMPOSE_FILES[@]}" up -d

# First-start defaults for Open WebUI. Its settings live in its database, so they are
# applied here after the container is up. Each default is only filled in if it was never
# set, so anything changed in the admin UI is left alone.
#  - Built-in tools off: Open WebUI sends its built-in tools (calendar, memory, notes, ...)
#    to every model, and small local models misfire on them (e.g. answering "hello" with a
#    search_calendar_events tool call).
#  - Web search on, using the SearXNG container from this repo. The container reaches the
#    host's published port 8080 through host.containers.internal.
configure_open_webui() {
    local result
    for _ in $(seq 1 60); do
        if result=$(podman exec -i open-webui python3 - 2>/dev/null <<'PY'
import json, sqlite3
db = sqlite3.connect("/app/backend/data/webui.db", timeout=30)

def get(key):
    row = db.execute("select value from config where key = ?", (key,)).fetchone()
    return None if row is None else json.loads(row[0]) if row[0] else None

def put(key, value):
    db.execute("update config set value = ? where key = ?", (json.dumps(value), key))

meta = get("models.default_metadata")
engine = get("web.search.engine")
if meta is None or engine is None:
    raise SystemExit(1)  # Open WebUI hasn't finished its first start yet

changed = False
caps = meta.setdefault("capabilities", {})
if "builtin_tools" not in caps:
    caps["builtin_tools"] = False
    put("models.default_metadata", meta)
    changed = True
if engine == "":
    put("web.search.engine", "searxng")
    put("web.search.searxng_query_url", "http://host.containers.internal:8080/search?q=<query>")
    put("web.search.enable", True)
    changed = True
db.commit()
print("changed" if changed else "unchanged")
PY
        ); then
            if [[ "$result" == "changed" ]]; then
                echo "==> Applied Open WebUI defaults (built-in tools off, SearXNG web search on); restarting it..."
                podman restart open-webui >/dev/null
            fi
            return 0
        fi
        sleep 2
    done
    echo "==> Could not update Open WebUI settings (is the open-webui container running?)" >&2
}

echo "==> Configuring Open WebUI..."
configure_open_webui

echo "==> Waiting for SearXNG to respond..."
for _ in $(seq 1 30); do
    if curl -s -o /dev/null http://localhost:8080; then
        echo "==> SearXNG is up at http://localhost:8080"
        echo "==> Open WebUI is at http://localhost:8081 (first start can take a minute)"
        echo "==> Ollama runs as a background service — open VS Code and use Cline."
        exit 0
    fi
    sleep 1
done

echo "==> SearXNG did not respond. Check: podman logs searxng" >&2
exit 1
