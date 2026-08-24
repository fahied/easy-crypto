#!/usr/bin/env bash
#
# list_traded_assets.sh — List every asset ever traded for spot, cross-margin,
# and isolated-margin, separately, by fetching trade history.
#
# Strategy:
#   1. Start with all active USDT pairs from /api/v1/exchangeInfo
#   2. For each day in the lookback window (3 months spot, 1 month margin):
#      - fetch all trades for all known symbols on that day
#      - extract any new symbols from the results
#   3. Output sorted unique base assets per mode
#
# Output:
#   ./traded-assets/spot.txt
#   ./traded-assets/cross-margin.txt
#   ./traded-assets/isolated-margin.txt
#
# Usage:
#   export BINANCE_API_KEY="your_key"
#   export BINANCE_API_SECRET="your_secret"
#   ./scripts/list_traded_assets.sh
#
# Requires: python3, curl, openssl
#
set -euo pipefail

if [[ -z "${BINANCE_API_KEY:-}" || -z "${BINANCE_API_SECRET:-}" ]]; then
    echo "ERROR: Set BINANCE_API_KEY and BINANCE_API_SECRET environment variables" >&2
    exit 1
fi

# ── Config ─────────────────────────────────────────────────────────────────────
API="https://api.binance.com"
LIMIT=1000
SPOT_MONTHS=3
MARGIN_MONTHS=1
SLEEP_BETWEEN=0.3        # seconds between API calls
OUT_DIR="./traded-assets"
mkdir -p "$OUT_DIR"

# ── Helpers ────────────────────────────────────────────────────────────────────

# Day start timestamps (seconds) using Python for portability
day_start_sec() {
    python3 -c "
from datetime import datetime, timezone, timedelta
import sys
start = datetime.now(timezone.utc) - timedelta(days=int(sys.argv[1]))
print(int(start.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()))
" "$1"
}

# ms_start, ms_end for a given day offset (0 = today)
day_range_ms() {
    python3 -c "
from datetime import datetime, timezone, timedelta
import sys
day_offset = int(sys.argv[1])
now = datetime.now(timezone.utc)
start = now - timedelta(days=day_offset)
start = start.replace(hour=0, minute=0, second=0, microsecond=0)
end = start + timedelta(days=1)
print(f'{int(start.timestamp() * 1000)} {int(end.timestamp() * 1000)}')
" "$1"
}

server_time_ms() {
    curl -sS --max-time 5 "${API}/api/v3/time" \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['serverTime'])"
}

sign() {
    printf '%s' "$1" \
        | openssl dgst -sha256 -hmac "$BINANCE_API_SECRET" \
        | awk '{print $2}'
}

# signed_get PATH QUERY TMPFILE
signed_get() {
    local path="$1" query="$2" out="$3"
    local ts
    ts=$(server_time_ms) || { echo "  ✗ could not reach server clock" >&2; return 1; }
    local full_query="${query}&timestamp=${ts}"
    local sig
    sig=$(sign "$full_query")
    local url="${API}${path}?${full_query}&signature=${sig}"

    local http_code
    http_code=$(curl -sS -o "$out" -w "%{http_code}" \
        -X GET "$url" \
        -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
        -H "Content-Type: application/json" \
        --max-time 30 2>/dev/null) || {
        echo "  ✗ curl failed" >&2; return 1
    }

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        echo "  ✗ HTTP $http_code — $(head -c 200 < "$out")" >&2
        if [[ "$http_code" == "429" || "$http_code" == "418" ]]; then
            echo "  ⏳ Rate-limited — sleeping 60 s…" >&2
            sleep 60
        fi
        return 1
    fi
}

# json_array_len FILE — count items in JSON array (0 on error)
json_array_len() {
    python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(len(data) if isinstance(data, list) else 0)
except Exception:
    print(0)
" "$1" 2>/dev/null
}

# Extract all symbols from trade JSON array
extract_symbols_from_trades() {
    python3 -c "
import json, sys
symbols = set()
try:
    trades = json.load(open(sys.argv[1]))
    if isinstance(trades, list):
        for t in trades:
            sym = t.get('symbol', '')
            if sym:
                symbols.add(sym)
except Exception:
    pass
for s in sorted(symbols):
    print(s)
" "$1" 2>/dev/null
}

# Extract sorted unique base assets from trade JSON array
extract_assets() {
    python3 -c "
import json, sys
seen = set()
try:
    trades = json.load(open(sys.argv[1]))
    if not isinstance(trades, list):
        trades = []
except Exception:
    trades = []
for t in trades:
    sym = t.get('symbol', '')
    if sym:
        base = sym
        for q in ('USDT', 'BUSD', 'BTC', 'ETH', 'BNB'):
            if sym.endswith(q) and len(sym) > len(q):
                base = sym[:-len(q)]
                break
        seen.add(base)
for a in sorted(seen):
    print(a)
" "$1" 2>/dev/null
}

# Append trades from src JSON array into dst JSON array
append_trades() {
    python3 -c "
import json, sys
src = sys.argv[1]
dst = sys.argv[2]
try:
    new = json.load(open(src))
    if not isinstance(new, list):
        sys.exit(0)
except Exception:
    sys.exit(0)
try:
    existing = json.load(open(dst))
    if not isinstance(existing, list):
        existing = []
except Exception:
    existing = []
existing.extend(new)
with open(dst, 'w') as f:
    json.dump(existing, f)
" "$1" "$2" 2>/dev/null
}

# ── Symbol Discovery ──────────────────────────────────────────────────────────

discover_spot_symbols() {
    local acct_ts acct_sig
    acct_ts=$(server_time_ms)
    acct_sig=$(sign "timestamp=${acct_ts}")

    curl -sS --max-time 15 \
        -X GET "${API}/api/v3/account?timestamp=${acct_ts}&signature=${acct_sig}" \
        -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
        -H "Content-Type: application/json" \
    | python3 -c '
import json, sys
acct = json.load(sys.stdin)
symbols = set()
for b in acct.get("balances", []):
    free = float(b.get("free", 0))
    locked = float(b.get("locked", 0))
    if free + locked > 0.0001:
        asset = b["asset"]
        if asset != "USDT":
            symbols.add(asset + "USDT")
for s in sorted(symbols):
    print(s)
'
}

discover_cross_symbols() {
    local acct_ts acct_sig
    acct_ts=$(server_time_ms)
    acct_sig=$(sign "timestamp=${acct_ts}")

    curl -sS --max-time 15 \
        -X GET "${API}/sapi/v1/margin/crossMargin?timestamp=${acct_ts}&signature=${acct_sig}" \
        -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
        -H "Content-Type: application/json" \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for a in data.get("assets", []):
        asset = a.get("asset", "")
        if asset and asset != "USDT":
            print(asset + "USDT")
except Exception:
    pass
'
}

# Get ALL active USDT pairs from exchange info
get_all_usdt_pairs() {
    curl -sS --max-time 15 "${API}/api/v1/exchangeInfo" \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
pairs = set()
for s in data.get("symbols", []):
    if s.get("status") == "TRADING" and s.get("quoteAsset") == "USDT":
        pairs.add(s["symbol"])
for p in sorted(pairs):
    print(p)
'
}

# ── Trade Fetching ────────────────────────────────────────────────────────────

# fetch_trades_in_window MODE OUTDIR SYMBOLS START_MS END_MS
# MODE: "spot" | "cross" | "isolated"
# Appends all trades from all symbols in the time window to ${OUTDIR}/${MODE}-trades.json
# Prints any newly discovered symbols (one per line)
fetch_trades_in_window() {
    local mode="$1" outdir="$2" shift_symbols="$3" start_ms="$4" end_ms="$5"
    local outfile="${outdir}/${mode}-trades.json"
    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" RETURN

    local is_iso="false"
    [[ "$mode" == "isolated" ]] && is_iso="true"

    local endpoint="/api/v3/myTrades"
    [[ "$mode" != "spot" ]] && endpoint="/sapi/v1/margin/myTrades"

    for symbol in $shift_symbols; do
        local query="symbol=${symbol}&limit=${LIMIT}&startTime=${start_ms}&endTime=${end_ms}"
        if ! signed_get "$endpoint" "$query" "$tmpfile"; then
            continue
        fi

        local count
        count=$(json_array_len "$tmpfile")
        if (( count == 0 )); then
            continue
        fi

        # Append to output
        append_trades "$tmpfile" "$outfile"
        sleep "$SLEEP_BETWEEN"
    done

    # Print newly discovered symbols
    extract_symbols_from_trades "$outfile"
}

# ── Per-Mode Fetch ────────────────────────────────────────────────────────────

# Iteratively discover and fetch all trades for a mode
# Args: mode outdir months
fetch_all_trades_for_mode() {
    local mode="$1" outdir="$2" months="$3"
    local outfile="${outdir}/${mode}-trades.json"
    local mode_label
    case "$mode" in
        spot)    mode_label="SPOT" ;;
        cross)   mode_label="CROSS-MARGIN" ;;
        isolated) mode_label="ISOLATED-MARGIN" ;;
    esac

    echo "  [${mode_label}] Discovering symbols..."

    # Step 1: Get initial symbol list
    local SYMBOLS=""
    case "$mode" in
        spot)    SYMBOLS=$(discover_spot_symbols) ;;
        cross)   SYMBOLS=$(discover_cross_symbols) ;;
        isolated) SYMBOLS=$(get_all_usdt_pairs) ;;
    esac

    if [[ -z "$SYMBOLS" ]]; then
        echo "  [${mode_label}] ⚠️  No initial symbols found — using defaults"
        SYMBOLS="BTCUSDT ETHUSDT BNBUSDT SOLUSDT DOGEUSDT XRPUSDT ADAUSDT AVAXUSDT DOTUSDT LINKUSDT"
    fi

    local sym_count
    sym_count=$(echo "$SYMBOLS" | wc -l | tr -d ' ')
    echo "  [${mode_label}] Starting with ${sym_count} symbols"

    # Step 2: Initialize output
    echo "[]" > "$outfile"

    # Step 3: Calculate day windows
    local total_days=$(( months * 30 ))
    local total_fetched=0

    echo "  [${mode_label}] Fetching ${total_days} days of trade history..."

    for (( day=0; day<total_days; day++ )); do
        local ms_range
        ms_range=$(day_range_ms "$day")
        local day_start_ms="${ms_range%% *}"
        local day_end_ms="${ms_range##* }"

        # Fetch trades for all current symbols in this day's window
        local new_symbols
        new_symbols=$(fetch_trades_in_window "$mode" "$outdir" "$SYMBOLS" "$day_start_ms" "$day_end_ms") || true

        # Update symbol list with any newly discovered symbols
        if [[ -n "$new_symbols" ]]; then
            local old_count
            old_count=$(echo "$SYMBOLS" | wc -l | tr -d ' ')
            SYMBOLS=$(echo -e "${SYMBOLS}\n${new_symbols}" | sort -u)
            local new_count
            new_count=$(echo "$SYMBOLS" | wc -l | tr -d ' ')
            if (( new_count > old_count )); then
                echo "  [${mode_label}]   +${new_count} symbols (was ${old_count})"
            fi
        fi

        local day_total
        day_total=$(json_array_len "$outfile")
        echo "  [${mode_label}]   Day ${day}/${total_days}: ${day_total} total trades"
    done

    local final_count
    final_count=$(json_array_len "$outfile")
    echo "  [${mode_label}] ✓ ${final_count} total trades fetched"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "=================================================================="
    echo "  List all traded assets — by mode (trade history)"
    echo "=================================================================="
    echo "  Spot lookback:    ${SPOT_MONTHS} months"
    echo "  Margin lookback:  ${MARGIN_MONTHS} month"
    echo "=================================================================="

    # ── Spot ─────────────────────────────────────────────────────────────────
    echo
    echo "── SPOT ────────────────────────────────────────────────────────────"
    local spot_out="${OUT_DIR}/spot-trades.json"
    fetch_all_trades_for_mode "spot" "$OUT_DIR" "$SPOT_MONTHS"
    extract_assets "$spot_out" > "${OUT_DIR}/spot.txt"

    local spot_count
    spot_count=$(wc -l < "${OUT_DIR}/spot.txt" | tr -d ' ')
    echo "  → ${spot_count} unique assets → ${OUT_DIR}/spot.txt"
    (( spot_count > 0 )) && cat "${OUT_DIR}/spot.txt" | sed 's/^/    /'

    # ── Cross-margin ─────────────────────────────────────────────────────────
    echo
    echo "── CROSS-MARGIN ────────────────────────────────────────────────────"
    local cross_out="${OUT_DIR}/cross-trades.json"
    fetch_all_trades_for_mode "cross" "$OUT_DIR" "$MARGIN_MONTHS"
    extract_assets "$cross_out" > "${OUT_DIR}/cross-margin.txt"

    local cross_count
    cross_count=$(wc -l < "${OUT_DIR}/cross-margin.txt" | tr -d ' ')
    echo "  → ${cross_count} unique assets → ${OUT_DIR}/cross-margin.txt"
    (( cross_count > 0 )) && cat "${OUT_DIR}/cross-margin.txt" | sed 's/^/    /'

    # ── Isolated-margin ──────────────────────────────────────────────────────
    echo
    echo "── ISOLATED-MARGIN ──────────────────────────────────────────────────"

    # Quick check: does isolated margin exist for this account?
    local acct_ts acct_sig iso_check
    acct_ts=$(server_time_ms)
    acct_sig=$(sign "timestamp=${acct_ts}")
    iso_check=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X GET "${API}/sapi/v1/margin/isolated/account?timestamp=${acct_ts}&signature=${acct_sig}" \
        -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
        -H "Content-Type: application/json" 2>/dev/null || true)

    if [[ "$iso_check" != "200" ]]; then
        echo "  ⚠️  Isolated margin not enabled (HTTP ${iso_check}) — skipping"
        echo "0" > "${OUT_DIR}/isolated-margin.txt"
    else
        local iso_out="${OUT_DIR}/iso-trades.json"
        fetch_all_trades_for_mode "isolated" "$OUT_DIR" "$MARGIN_MONTHS"
        extract_assets "$iso_out" > "${OUT_DIR}/isolated-margin.txt"
    fi

    local iso_count
    iso_count=$(wc -l < "${OUT_DIR}/isolated-margin.txt" | tr -d ' ')
    echo "  → ${iso_count} unique assets → ${OUT_DIR}/isolated-margin.txt"
    (( iso_count > 0 )) && cat "${OUT_DIR}/isolated-margin.txt" | sed 's/^/    /'

    # ── Summary ──────────────────────────────────────────────────────────────
    echo
    echo "=================================================================="
    echo "  SUMMARY"
    echo "=================================================================="
    printf "  %-18s %s\n" "Spot"            "(${spot_count} assets)"
    printf "  %-18s %s\n" "Cross-margin"    "(${cross_count} assets)"
    printf "  %-18s %s\n" "Isolated-margin" "(${iso_count} assets)"
    echo
    echo "  Output written to ${OUT_DIR}/"
    ls -1 "${OUT_DIR}"/*.txt
    echo
    echo "  (Spot: ${SPOT_MONTHS} months history, Margin: ${MARGIN_MONTHS} month)"
    echo "  Trade data preserved in ${OUT_DIR}/*-trades.json"
    echo
}

main
