#!/usr/bin/env python3
"""
audit_current_value.py — Calculate portfolio currentValueUSDT from Binance API.

Mirrors exactly what the app does:
  - Spot:    quantity = free + locked  (from /api/v3/account?omitZeroBalances=true)
  - Cross:   quantity = netAsset        (from /sapi/v1/margin/account)
  - Isolated:quantity = netAsset        (from /sapi/v1/margin/isolated/account)
  - Price:   lastPrice from /api/v3/ticker/price

Usage:
  python3 scripts/audit_current_value.py <API_KEY> <API_SECRET>

Env (optional, fallback to args):
  BINANCE_API_KEY, BINANCE_API_SECRET
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import sys
import time
import urllib.parse
import urllib.request

# ─── Config ────────────────────────────────────────────────────────────────────

API_KEY = os.environ.get("BINANCE_API_KEY") or (sys.argv[1] if len(sys.argv) > 1 else "")
API_SECRET = os.environ.get("BINANCE_API_SECRET") or (sys.argv[2] if len(sys.argv) > 2 else "")
BASE_URL = "https://api.binance.com"

if not API_KEY or not API_SECRET:
    print("ERROR: Provide BINANCE_API_KEY and BINANCE_API_SECRET as env vars or args")
    sys.exit(1)

# ─── HTTP helpers ──────────────────────────────────────────────────────────────


def signed_get(path: str, params: dict) -> dict:
    """GET a signed Binance endpoint and return parsed JSON."""
    params["timestamp"] = int(time.time() * 1000)
    query = urllib.parse.urlencode(params)
    signature = hmac.new(
        API_SECRET.encode(), query.encode(), hashlib.sha256
    ).hexdigest()
    url = f"{BASE_URL}{path}?{query}&signature={signature}"
    req = urllib.request.Request(url, headers={"X-MBX-APIKEY": API_KEY})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def public_get(path: str, params: dict) -> dict | list:
    """GET a public Binance endpoint and return parsed JSON."""
    query = urllib.parse.urlencode(params)
    url = f"{BASE_URL}{path}?{query}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


# ─── Data fetching ─────────────────────────────────────────────────────────────


def fetch_spot_balances() -> list[dict]:
    """GET /api/v3/account?omitZeroBalances=true"""
    data = signed_get("/api/v3/account", {"omitZeroBalances": "true"})
    return data.get("balances", [])


def fetch_cross_margin() -> dict:
    """GET /sapi/v1/margin/account — full account snapshot."""
    return signed_get("/sapi/v1/margin/account", {})


def fetch_isolated_margin() -> dict:
    """GET /sapi/v1/margin/isolated/account — all isolated pairs."""
    return signed_get("/sapi/v1/margin/isolated/account", {})


def fetch_prices(symbols: list[str]) -> dict[str, float]:
    """GET /api/v3/ticker/price — one symbol per request (public endpoint)."""
    prices: dict[str, float] = {}
    for symbol in symbols:
        try:
            data = public_get("/api/v3/ticker/price", {"symbol": symbol})
            prices[data["symbol"]] = float(data["price"])
        except Exception as e:
            print(f"   ⚠️  No price for {symbol}: {e}")
    return prices


# ─── Calculation (mirrors the app) ────────────────────────────────────────────


def compute_spot(balances_raw: list[dict], prices: dict[str, float]) -> tuple[float, dict]:
    """
    Spot: quantity = free + locked, same filter as BalanceService.live.
    Returns (total_current_value, per_asset_breakdown).
    """
    assets: dict[str, float] = {}
    for b in balances_raw:
        free = float(b["free"])
        locked = float(b["locked"])
        if free + locked > 0:
            assets[b["asset"]] = free + locked

    breakdown = {}
    total = 0.0
    for asset, qty in sorted(assets.items()):
        if asset == "USDT":
            price = 1.0
        else:
            price = prices.get(f"{asset}USDT", 0.0)
        value = qty * price
        breakdown[asset] = {"quantity": qty, "price": price, "value": value}
        total += value
    return total, breakdown


def compute_cross_margin(account: dict, prices: dict[str, float]) -> tuple[float, dict]:
    """
    Cross-margin: quantity = netAsset (= free + locked - borrowed - interest).
    Uses userAssets[].netAsset, falling back to free+locked-borrowed-interest.
    """
    breakdown = {}
    total = 0.0
    for entry in account.get("userAssets", []):
        asset = entry.get("asset", "")
        if not asset:
            continue
        net_asset = float(entry.get("netAsset") or "0")
        if net_asset == 0:
            # fallback
            free = float(entry.get("free") or "0")
            locked = float(entry.get("locked") or "0")
            borrowed = float(entry.get("borrowed") or "0")
            interest = float(entry.get("interest") or "0")
            net_asset = free + locked - borrowed - interest
        if net_asset == 0:
            continue
        if asset == "USDT":
            price = 1.0
        else:
            price = prices.get(f"{asset}USDT", 0.0)
        value = net_asset * price
        breakdown[asset] = {
            "quantity": net_asset,
            "price": price,
            "value": value,
            "free": float(entry.get("free") or "0"),
            "locked": float(entry.get("locked") or "0"),
            "borrowed": float(entry.get("borrowed") or "0"),
            "interest": float(entry.get("interest") or "0"),
        }
        total += value
    return total, breakdown


def compute_isolated_margin(account: dict, prices: dict[str, float]) -> tuple[float, dict]:
    """
    Isolated-margin: quantity = netAsset per baseAsset in each isolated pair.
    """
    breakdown = {}
    total = 0.0
    for pair in account.get("assets", []):
        base = pair.get("baseAsset", {})
        asset = base.get("asset", "")
        if not asset:
            continue
        net_asset = float(base.get("netAsset") or "0")
        if net_asset == 0:
            continue
        if asset == "USDT":
            price = 1.0
        else:
            price = prices.get(f"{asset}USDT", 0.0)
        value = net_asset * price
        key = f"{pair.get('symbol', '')}#{asset}"
        breakdown[key] = {
            "symbol": pair.get("symbol"),
            "quantity": net_asset,
            "price": price,
            "value": value,
        }
        total += value
    return total, breakdown


# ─── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    print("=" * 64)
    print("  currentValueUSDT audit — mirrors EasyCrypto app logic")
    print("=" * 64)

    # 1. Fetch all data
    print("\n⏳ Fetching balances and prices...")
    spot_balances = fetch_spot_balances()
    cross_account = fetch_cross_margin()
    isolated_account = fetch_isolated_margin()

    # Collect all non-USDT symbols for price lookup
    all_symbols = set()
    for b in spot_balances:
        asset = b["asset"]
        if asset != "USDT" and (float(b["free"]) + float(b["locked"])) > 0:
            all_symbols.add(f"{asset}USDT")
    for entry in cross_account.get("userAssets", []):
        asset = entry.get("asset", "")
        if asset and asset != "USDT" and float(entry.get("netAsset") or "0") > 0:
            all_symbols.add(f"{asset}USDT")
    for pair in isolated_account.get("assets", []):
        base = pair.get("baseAsset", {})
        asset = base.get("asset", "")
        if asset and asset != "USDT" and float(base.get("netAsset") or "0") > 0:
            all_symbols.add(f"{asset}USDT")

    prices = fetch_prices(sorted(all_symbols))
    print(f"   Fetched {len(prices)} prices")

    # 2. Compute per mode
    spot_total, spot_detail = compute_spot(spot_balances, prices)
    cross_total, cross_detail = compute_cross_margin(cross_account, prices)
    isolated_total, isolated_detail = compute_isolated_margin(isolated_account, prices)

    grand_total = spot_total + cross_total + isolated_total

    # 3. Report
    print(f"\n{'─' * 64}")
    print(f"  CURRENT VALUE BREAKDOWN")
    print(f"{'─' * 64}")
    print(f"  {'Mode':<16} {'Value (USDT)':>14}")
    print(f"  {'─' * 16} {'─' * 14}")
    print(f"  {'Spot':<16} {spot_total:>14,.2f}")
    print(f"  {'Cross-Margin':<16} {cross_total:>14,.2f}")
    print(f"  {'Isolated-Margin':<16} {isolated_total:>14,.2f}")
    print(f"  {'─' * 16} {'─' * 14}")
    print(f"  {'TOTAL':<16} {grand_total:>14,.2f}")

    # 4. Per-asset detail
    if spot_detail:
        print(f"\n{'─' * 64}")
        print(f"  SPOT HOLDINGS")
        print(f"  {'Asset':<12} {'Qty':>18} {'Price':>12} {'Value':>14}")
        print(f"  {'─' * 12} {'─' * 18} {'─' * 12} {'─' * 14}")
        for asset, d in sorted(spot_detail.items(), key=lambda x: -x[1]["value"]):
            if d["value"] > 0:
                print(
                    f"  {asset:<12} {d['quantity']:>18.8f} {d['price']:>12.2f} {d['value']:>14,.2f}"
                )

    if cross_detail:
        print(f"\n{'─' * 64}")
        print(f"  CROSS-MARGIN HOLDINGS")
        print(
            f"  {'Asset':<12} {'NetAsset':>10} {'Free':>12} {'Locked':>12} {'Borrowed':>10} {'Interest':>10} {'Price':>10} {'Value':>12}"
        )
        print(
            f"  {'─' * 12} {'─' * 10} {'─' * 12} {'─' * 12} {'─' * 10} {'─' * 10} {'─' * 10} {'─' * 12}"
        )
        for asset, d in sorted(cross_detail.items(), key=lambda x: -x[1]["value"]):
            if d["value"] > 0:
                print(
                    f"  {asset:<12} {d['quantity']:>10.8f} {d['free']:>12.8f} {d['locked']:>12.8f} "
                    f"{d['borrowed']:>10.8f} {d['interest']:>10.8f} {d['price']:>10.2f} {d['value']:>12,.2f}"
                )

    if isolated_detail:
        print(f"\n{'─' * 64}")
        print(f"  ISOLATED-MARGIN HOLDINGS")
        print(
            f"  {'Pair#Asset':<22} {'NetAsset':>10} {'Price':>10} {'Value':>12}"
        )
        print(
            f"  {'─' * 22} {'─' * 10} {'─' * 10} {'─' * 12}"
        )
        for key, d in sorted(isolated_detail.items(), key=lambda x: -x[1]["value"]):
            if d["value"] > 0:
                print(
                    f"  {key:<22} {d['quantity']:>10.8f} {d['price']:>10.2f} {d['value']:>12,.2f}"
                )

    # 5. Compare spot quantity sources
    print(f"\n{'─' * 64}")
    print(f"  SPOT: balance API vs FIFO remaining quantity")
    print(f"  (balances come from /api/v3/account; FIFO qty is from trade history)")
    print(f"  {'Asset':<12} {'API Qty':>14} {'Note':>20}")
    print(f"  {'─' * 12} {'─' * 14} {'─' * 20}")
    for b in sorted(spot_balances, key=lambda x: x["asset"]):
        asset = b["asset"]
        qty = float(b["free"]) + float(b["locked"])
        if qty > 0:
            note = "USDT" if asset == "USDT" else f"≈ {asset}USDT price"
            print(f"  {asset:<12} {qty:>14.8f} {note:>20}")

    # 6. Warn about zero-price assets
    zero_price = []
    for asset, d in spot_detail.items():
        if d["price"] == 0 and asset != "USDT":
            zero_price.append(asset)
    for asset, d in cross_detail.items():
        if d["price"] == 0 and asset != "USDT":
            zero_price.append(asset)
    if zero_price:
        print(f"\n⚠️  WARNING: Zero price for: {', '.join(sorted(set(zero_price)))}")
        print("   These assets contribute 0 to currentValueUSDT.")
        print("   Possible causes: not traded against USDT, price API issue, delisted.")

    print(f"\n{'═' * 64}")
    print(f"  TOTAL currentValueUSDT: {grand_total:>14,.2f} USDT")
    print(f"{'═' * 64}")
    print()
    print("Compare this TOTAL with the 'Portfolio' or 'Holdings' tab value")
    print("in the app. Any difference is your 2-3% discrepancy to investigate.")
    print()


if __name__ == "__main__":
    main()
