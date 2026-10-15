#!/bin/bash
# Real Keychain coverage is deliberately restricted to GitHub's macOS runner.
# A wrapper supplies an explicit keychain to every command; the login keychain
# and the user's default/search-list settings are never changed.
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != "true" || "$OSTYPE" != darwin* ]]; then
    echo "This test only runs on a GitHub Actions macOS runner." >&2
    exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
export TEST_KEYCHAIN="$TEST_DIR/test.keychain-db"
cleanup() {
    /usr/bin/security delete-keychain "$TEST_KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
/usr/bin/security create-keychain -p "$PASSWORD" "$TEST_KEYCHAIN"
/usr/bin/security unlock-keychain -p "$PASSWORD" "$TEST_KEYCHAIN"
mkdir "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/security" <<'SH'
#!/bin/bash
set -euo pipefail
case "$1" in
    find-generic-password|add-generic-password|delete-generic-password)
        exec /usr/bin/security "$@" "$TEST_KEYCHAIN"
        ;;
    *) echo "Unexpected Keychain operation: $1" >&2; exit 1 ;;
esac
SH
chmod +x "$TEST_DIR/bin/security"
export PATH="$TEST_DIR/bin:$PATH"

get_key() {
    security find-generic-password -a "$USER" -s "SearXNG Secret Key" -w
}

# Suppress script output because the setup/show scripts print the secret.
bash "$ROOT/searxng-keychain-setup.sh" > /dev/null
FIRST=$(get_key)
[[ ${#FIRST} -eq 43 ]]
bash "$ROOT/searxng-keychain-setup.sh" > /dev/null
SECOND=$(get_key)
[[ ${#SECOND} -eq 43 && "$SECOND" != "$FIRST" ]]
bash "$ROOT/searxng-keychain-usage.sh" show > /dev/null
bash "$ROOT/searxng-keychain-usage.sh" reset > /dev/null
THIRD=$(get_key)
[[ ${#THIRD} -eq 43 && "$THIRD" != "$SECOND" ]]
bash "$ROOT/searxng-keychain-usage.sh" remove > /dev/null
if get_key > /dev/null 2>&1; then
    echo "Key was not removed from the test keychain." >&2
    exit 1
fi
echo "Isolated Keychain lifecycle passed."