#!/usr/bin/env bash
#
# Fetch all spot trades executed on Binance in July 2026 and save to JSON.
#
# Usage:
#   export BINANCE_API_KEY="your_key"
#   export BINANCE_API_SECRET="your_secret"
#   ./binance-july-trades.sh [output_dir]
#
# Output: one JSON file per symbol → <output_dir>/<SYMBOL>.json

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
API="https://api.binance.com"
ENDPOINT="/api/v3/myTrades"
LIMIT=1000
START_TS=$(date -u -j -f "%Y-%m-%d" "2026-07-01" "+%s")000   # 2026-07-01 00:00 UTC
END_TS=$(date -u -j -f "%Y-%m-%d" "2026-08-01" "+%s")000     # 2026-08-01 00:00 UTC
OUT_DIR="${1:-./binance-trades-july2026}"
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

# ── Step 1 — discover active symbols ────────────────────────────────────────
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
    print("")  # empty → fallback downstream
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

# ── Step 2 — fetch trades per symbol (daily 24h windows) ────────────────────
# Binance enforces endTime - startTime <= 24h, so we iterate day by day.
JULY_START_MS=$START_TS
JULY_END_MS=$END_TS
DAY_MS=$((24 * 60 * 60 * 1000))

FAILED=0
for SYM in $SYMBOLS; do
  OUTFILE="${OUT_DIR}/${SYM}.json"
  TMPFILE=$(mktemp)

  echo -n "▸ ${SYM} … "

  # Write all pages across all days into this file
  FIRST_WRITE=1
  TOTAL_DAYS=0

  WINDOW_START=$JULY_START_MS
  while (( WINDOW_START < JULY_END_MS )); do
    WINDOW_END=$(( WINDOW_START + DAY_MS ))
    (( WINDOW_END > JULY_END_MS )) && WINDOW_END=$JULY_END_MS

    FROM_ID=""
    while :; do
      QUERY="symbol=${SYM}&startTime=${WINDOW_START}&endTime=${WINDOW_END}&limit=${LIMIT}"
      [[ -n "$FROM_ID" ]] && QUERY="${QUERY}&fromId=${FROM_ID}"

      if ! api_get "$QUERY" "$TMPFILE"; then
        FAILED=$((FAILED + 1))
        rm -f "$TMPFILE"
        break 2       # skip to next symbol on non-recoverable failure
      fi

      COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$TMPFILE" 2>/dev/null || echo 0)

      if (( COUNT == 0 )); then
        rm -f "$TMPFILE"
        break
      fi

      if (( FIRST_WRITE )); then
        mv "$TMPFILE" "$OUTFILE"
        FIRST_WRITE=0
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

    WINDOW_START=$WINDOW_END
    TOTAL_DAYS=$((TOTAL_DAYS + 1))
  done

  # Deduplicate by trade id
  if [[ -f "$OUTFILE" ]]; then
    TOTAL=$(python3 -c "
import json,sys
t=json.load(open(sys.argv[1]))
seen=set(); dedup=[]
for trade in t:
    if trade['id'] not in seen:
        seen.add(trade['id']); dedup.append(trade)
with open(sys.argv[1],'w') as f: json.dump(dedup,f)
print(len(dedup))
" "$OUTFILE")
    echo "→ ${TOTAL} trades (${TOTAL_DAYS}d)"
  fi
done

echo
echo "────────────────────────────────────"
echo "Done. ${OUT_DIR}/ — symbols with failures: ${FAILED}"
ls -lh "$OUT_DIR"
