#!/usr/bin/env bash
#
# audit_avg_buy_price.sh — Compute weighted avg buy price from Binance API trade history
# for a given symbol, per trading mode, and compare with the app's FIFO calculation.
#
# Usage:
#   export BINANCE_API_KEY="your_key"
#   export BINANCE_API_SECRET="your_secret"
#   ./scripts/audit_avg_buy_price.sh XRPUSDT
#   ./scripts/audit_avg_buy_price.sh XRPUSDT --mode spot
#   ./scripts/audit_avg_buy_price.sh XRPUSDT --mode all
#
# Requires: python3
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/audit_avg_buy_price.py"

if [[ -z "${BINANCE_API_KEY:-}" || -z "${BINANCE_API_SECRET:-}" ]]; then
    echo "ERROR: Set BINANCE_API_KEY and BINANCE_API_SECRET environment variables"
    exit 1
fi

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "ERROR: Missing $PYTHON_SCRIPT"
    exit 1
fi

exec python3 "$PYTHON_SCRIPT" "$@"
