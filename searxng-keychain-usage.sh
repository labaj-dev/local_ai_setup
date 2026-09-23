#!/bin/bash

# SearXNG Keychain Usage Script
# This script helps manage your SearXNG secret key from Keychain

set -e

KEYCHAIN_ITEM_NAME="SearXNG Secret Key"

echo "SearXNG Keychain Management"
echo "=========================="

if [[ "$1" == "show" ]]; then
    # Show the current key
    if security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" &>/dev/null; then
        KEY=$(security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" -w)
        echo "Current SearXNG secret key: $KEY"
    else
        echo "No key found in Keychain with name: $KEYCHAIN_ITEM_NAME"
    fi
    
elif [[ "$1" == "reset" ]]; then
    # Generate and store a new key
    echo "Generating new secure key..."
    NEW_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    
    if security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" &>/dev/null; then
        echo "Updating existing key in Keychain..."
        security add-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" -p "$NEW_KEY" -w -U
    else
        echo "Creating new key in Keychain..."
        security add-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" -p "$NEW_KEY" -w -U
    fi
    
    echo "New key has been set in Keychain."
    echo "You can now restart your SearXNG container with the new key."
    
elif [[ "$1" == "remove" ]]; then
    # Remove the key from Keychain (optional)
    if security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME" &>/dev/null; then
        echo "Removing key from Keychain..."
        security delete-generic-password -a "$USER" -s "$KEYCHAIN_ITEM_NAME"
        echo "Key removed successfully."
    else
        echo "No key found in Keychain to remove."
    fi
    
else
    # Show help
    echo "Usage: $0 [show|reset|remove]"
    echo ""
    echo "  show    - Display the current key"
    echo "  reset   - Generate and store a new key"
    echo "  remove  - Remove the key from Keychain (optional)"
    echo ""
    echo "To use this key in your shell session:"
    echo "  export SEARXNG_SECRET_KEY=\$(security find-generic-password -a \$USER -s \"$KEYCHAIN_ITEM_NAME\" -w)"
fi