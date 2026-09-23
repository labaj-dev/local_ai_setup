#!/bin/bash

# SearXNG Keychain Setup Script
# This script sets up a secure secret key for SearXNG using macOS Keychain

set -e  # Exit on any error

KEYCHAIN_ITEM_NAME="SearXNG Secret Key"
KEYCHAIN_ACCESS_GROUP="searxng-keychain"

echo "Setting up SearXNG secret key in macOS Keychain..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi

# Check if security command exists
if ! command -v security &> /dev/null; then
    echo "Error: security command not found. Is Keychain Access available?"
    exit 1
fi

# Generate a secure random key (32 bytes = 43 characters in base64)
echo "Generating secure random key..."
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

# Check if key already exists in Keychain
if security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" &>/dev/null; then
    echo "Key already exists in Keychain. Updating..."
    # Update existing key
    security add-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" -p "$SECRET_KEY" -w -U
else
    # Create new key
    echo "Creating new key in Keychain..."
    security add-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" -p "$SECRET_KEY" -w -U
fi

# Export the key to current environment
export SEARXNG_SECRET_KEY="$SECRET_KEY"

echo "Key successfully stored in Keychain and exported to environment."
echo "Secret key: $SECRET_KEY"
echo ""
echo "To use this key in your shell session, run:"
echo "  export SEARXNG_SECRET_KEY=\$(security find-generic-password -a \$USER -s \"$KEYCHAIN_ITEM_NAME\" -w)"
echo ""
echo "To make it permanent, add the following line to your ~/.zshrc or ~/.bash_profile:"
echo "  export SEARXNG_SECRET_KEY=\$(security find-generic-password -a \$USER -s \"$KEYCHAIN_ITEM_NAME\" -w)"