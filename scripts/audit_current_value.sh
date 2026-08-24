#!/usr/bin/env bash
#
# audit_current_value.sh — Calculate portfolio currentValueUSDT from Binance API
# and compare with what the app reports.
#
# Usage:
#   export BINANCE_API_KEY="your_key"
#   export BINANCE_API_SECRET="your_secret"
#   ./scripts/audit_current_value.sh
#
# Requires: python3, curl, openssl
#
set -euo pipefail

if [[ -z "${BINANCE_API_KEY:-}" || -z "${BINANCE_API_SECRET:-}" ]]; then
    echo "ERROR: Set BINANCE_API_KEY and BINANCE_API_SECRET environment variables"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/audit_current_value.py"

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "ERROR: Missing $PYTHON_SCRIPT"
    exit 1
fi

exec python3 "$PYTHON_SCRIPT" "$BINANCE_API_KEY" "$BINANCE_API_SECRET"
