#!/usr/bin/env bash
#
# Fetch all spot trades executed on Binance in July 2026, one JSON file per day.
#
# Usage:
#   export BINANCE_API_KEY="your_key"
#   export BINANCE_API_SECRET="your_secret"
#   ./binance-july-trades.sh [output_dir] [--date YYYY-MM-DD]
#
# Output (no --date): one JSON file per July 2026 calendar day
# Output (--date): single JSON file for that date
#
# Options:
#   --date YYYY-MM-DD   Fetch only this date's trades
#   --out-dir DIR        Output directory (default: ./binance-trades-july2026)

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
API="https://api.binance.com"
ENDPOINT="/api/v3/myTrades"
LIMIT=1000

# ── Arguments ────────────────────────────────────────────────────────────────
SINGLE_DATE=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)     SINGLE_DATE="$2"; shift 2 ;;
    --out-dir)  OUT_DIR="$2"; shift 2 ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          OUT_DIR="$1"; shift ;;
  esac
done

OUT_DIR="${OUT_DIR:-./binance-trades-july2026}"
DEFAULT_START="2026-07-01"
DEFAULT_END="2026-08-01"

# ── Pre-flight ──────────────────────────────────────────────────────────────
if [[ -z "${BINANCE_API_KEY:-}" || -z "${BINANCE_API_SECRET:-}" ]]; then
  echo "ERROR: Set BINANCE_API_KEY and BINANCE_API_SECRET in your environment." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
echo "Output directory: $OUT_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────
# Use Binance's own server time as the request timestamp — eliminates all
# clock-skew issues (Binance tolerates its own time unconditionally).
# Re-fetches each call; the overhead is one cheap unauthenticated GET.
server_time_ms() {
  curl -sS --max-time 5 "${API}/api/v3/time" | python3 -c "import json,sys; print(json.load(sys.stdin)['serverTime'])"
}

sign() {
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$BINANCE_API_SECRET" | awk '{print $2}'
}

api_get() {
  local ts
  ts=$(server_time_ms) || { echo "  ✗ could not reach server clock" >&2; return 1; }

  local query="${1}&timestamp=${ts}"
  local sig
  sig=$(sign "$query")
  local url="${API}${ENDPOINT}?${query}&signature=${sig}"

  local http_code body
  http_code=$(curl -sS -o "$2" -w "%{http_code}" \
    -X GET "$url" \
    -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
    -H "Content-Type: application/json" \
    --max-time 30) || {
      echo "  ✗ curl failed for $url" >&2
      return 1
    }

  if [[ "$http_code" == "200" ]]; then
    return 0
  else
    body=$(cat "$2")
    echo "  ✗ HTTP $http_code — $(echo "$body" | head -c 200)" >&2
    # Prune rate-limit so we don't hammer the API
    if [[ "$http_code" == "429" || "$http_code" == "418" ]]; then
      echo "  ⏳ Rate-limited — sleeping 60 s…" >&2
      sleep 60
    fi
    return 1
  fi
}

# ── Symbols ──────────────────────────────────────────────────────────────────
echo "Fetching account snapshot to discover active symbols…"

ACCT_JSON=$(mktemp)
ACCT_TS=$(server_time_ms) || { ACCT_TS=""; }
ACCT_QUERY="timestamp=${ACCT_TS}"
ACCT_SIG=$(sign "$ACCT_QUERY")

if ! curl -sS -o "$ACCT_JSON" \
  -X GET "${API}/api/v3/account?${ACCT_QUERY}&signature=${ACCT_SIG}" \
  -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
  -H "Content-Type: application/json" \
  --max-time 30; then
  echo "WARNING: Could not reach Binance account endpoint. Falling back to a default list." >&2
  SYMBOLS="BTCUSDT ETHUSDT BNBUSDT SOLUSDT DOGEUSDT XRPUSDT ADAUSDT AVAXUSDT DOTUSDT LINKUSDT"
else
  SYMBOLS=$(python3 -c '
import sys, json
acct = json.load(open(sys.argv[1]))
if "balances" not in acct:
    print("")
    sys.exit(0)
assets = {b["asset"] for b in acct["balances"] if float(b["free"]) > 0 or float(b["locked"]) > 0}
pairs = set()
for a in assets:
    for quote in ("USDT", "BUSD", "BTC", "ETH", "BNB"):
        pairs.add(f"{a}{quote}")
print(" ".join(sorted(pairs)))
' "$ACCT_JSON")
fi
rm -f "$ACCT_JSON"

if [[ -z "$SYMBOLS" ]]; then
  echo "WARNING: No symbols discovered. Falling back to a default list." >&2
  SYMBOLS="BTCUSDT ETHUSDT BNBUSDT SOLUSDT DOGEUSDT XRPUSDT ADAUSDT AVAXUSDT DOTUSDT LINKUSDT"
fi

echo "Symbols to fetch: ${SYMBOLS}"
echo

# ── Date range ───────────────────────────────────────────────────────────────
if [[ -n "$SINGLE_DATE" ]]; then
  RANGE_START_TS=$(date -u -j -f "%Y-%m-%d" "$SINGLE_DATE" "+%s")000
  RANGE_END_TS=$(( RANGE_START_TS + 24 * 60 * 60 * 1000 ))
else
  RANGE_START_TS=$(date -u -j -f "%Y-%m-%d" "$DEFAULT_START" "+%s")000
  RANGE_END_TS=$(date -u -j -f "%Y-%m-%d" "$DEFAULT_END" "+%s")000
fi

DAY_MS=$((24 * 60 * 60 * 1000))

FAILED=0
WINDOW_START=$RANGE_START_TS
DAY_INDEX=0

while (( WINDOW_START < RANGE_END_TS )); do
  DAY_INDEX=$((DAY_INDEX + 1))
  WINDOW_END=$(( WINDOW_START + DAY_MS ))
  (( WINDOW_END > RANGE_END_TS )) && WINDOW_END=$RANGE_END_TS

  # File name: 2026-07-01.json
  DAY_DATE=$(date -u -j -f "%s" "$(( WINDOW_START / 1000 ))" "+%Y-%m-%d")
  OUTFILE="${OUT_DIR}/${DAY_DATE}.json"
  TMPFILE=$(mktemp)

  echo "[${DAY_INDEX}] ${DAY_DATE} … "

  # Collect all symbol pages for this day into a single array
  FIRST=1

  for SYM in $SYMBOLS; do
    FROM_ID=""
    while :; do
      QUERY="symbol=${SYM}&startTime=${WINDOW_START}&endTime=${WINDOW_END}&limit=${LIMIT}"
      [[ -n "$FROM_ID" ]] && QUERY="${QUERY}&fromId=${FROM_ID}"

      if ! api_get "$QUERY" "$TMPFILE"; then
        FAILED=$((FAILED + 1))
        rm -f "$TMPFILE"
        break 2
      fi

      COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$TMPFILE" 2>/dev/null || echo 0)

      if (( COUNT == 0 )); then
        rm -f "$TMPFILE"
        break
      fi

      # Merge this page into the day's accumulator
      if (( FIRST )); then
        mv "$TMPFILE" "$OUTFILE"
        FIRST=0
      else
        python3 -c "
import json,sys
existing=json.load(open(sys.argv[1]))
new=json.load(open(sys.argv[2]))
existing.extend(new)
with open(sys.argv[1],'w') as f: json.dump(existing,f)
" "$OUTFILE" "$TMPFILE"
        rm -f "$TMPFILE"
      fi

      echo -n "${COUNT} "

      if (( COUNT < LIMIT )); then
        break
      fi

      FROM_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin)[-1]['id'])" < "$OUTFILE")
      sleep 0.25
    done
  done

  # Normalize Binance fields → validator-friendly format, deduplicate, sort
  if [[ -f "$OUTFILE" ]]; then
    TOTAL=$(python3 -c "
import json, sys
trades = json.load(open(sys.argv[1]))
seen = set()
dedup = []
for t in trades:
    tid = t.get('id')
    if tid in seen:
        continue
    seen.add(tid)
    # Normalize Binance field names
    symbol = t.get('symbol', '')
    for _q in ('USDT', 'BUSD', 'BTC', 'ETH', 'BNB'):
        if symbol.endswith(_q):
            asset = symbol[:-len(_q)]
            break
    else:
        asset = symbol
    ts_ms = t.get('time', 0)
    date = __import__('datetime').datetime.fromtimestamp(ts_ms / 1000, tz=__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    dedup.append({
        'id': tid,
        'date': date,
        'asset': asset,
        'symbol': symbol,
        'price': float(t.get('price', 0)),
        'quantity': float(t.get('qty', 0)),
        'quoteQuantity': float(t.get('quoteQty', 0)),
        'commission': float(t.get('commission', 0)),
        'commissionAsset': t.get('commissionAsset', ''),
        'isBuyer': bool(t.get('isBuyer', False)),
        'tradingMode': 'spot',
    })
dedup.sort(key=lambda x: x['date'])
with open(sys.argv[1], 'w') as f:
    json.dump(dedup, f, indent=2)
print(len(dedup))
" "$OUTFILE")
    echo "→ ${TOTAL} trades"
  else
    # No trades for this day — write an empty array so the file exists
    echo "[]" > "$OUTFILE"
    echo "→ 0 trades"
  fi

  WINDOW_START=$WINDOW_END
done

echo
echo "────────────────────────────────────"
echo "Done. ${OUT_DIR}/ — symbols with failures: ${FAILED}"
ls -lh "$OUT_DIR"
