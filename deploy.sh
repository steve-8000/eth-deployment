#!/usr/bin/env bash
# Wrapper script for bin/deploy
# This allows running ./deploy.sh from project root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/bin/deploy" "$@"
