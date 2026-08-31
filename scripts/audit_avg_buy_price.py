#!/usr/bin/env python3
"""
audit_avg_buy_price.py — Compute weighted avg buy price from Binance trade history
for a given symbol, per trading mode, using FIFO lot logic.

Mirrors the app's FIFO engine:
  - Buys create lots (price, qty adjusted for base-asset commission)
  - Sells consume earliest lots first
  - Weighted avg = sum(price * remainingQty) / sum(remainingQty) over surviving lots

Usage:
  # Spot (default)
  BINANCE_API_KEY=... BINANCE_API_SECRET=... python3 scripts/audit_avg_buy_price.py XRPUSDT

  # Cross-margin
  python3 scripts/audit_avg_buy_price.py XRPUSDT --mode cross

  # Isolated-margin
  python3 scripts/audit_avg_buy_price.py XRPUSDT --mode isolated

  # All modes at once
  python3 scripts/audit_avg_buy_price.py XRPUSDT --mode all
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.parse
import urllib.request

# ─── Config ─────────────────────────────────────────────────────────────────────

API_KEY = os.environ.get("BINANCE_API_KEY", "")
API_SECRET = os.environ.get("BINANCE_API_SECRET", "")
BASE_URL = "https://api.binance.com"

if not API_KEY or not API_SECRET:
    print("ERROR: Set BINANCE_API_KEY and BINANCE_API_SECRET environment variables")
    sys.exit(1)

# ─── Clock sync ────────────────────────────────────────────────────────────────

_binance_server_time_ms: int = 0
_local_time_at_sync: float = 0.0


def sync_clock() -> None:
    global _local_time_at_sync, _binance_server_time_ms
    _local_time_at_sync = time.time()
    _binance_server_time_ms = int(public_get("/api/v3/time", {})["serverTime"])
    print(f"  Clock sync: server offset {_binance_server_time_ms - int(_local_time_at_sync * 1000):+d}ms")


def now_ms() -> int:
    return _binance_server_time_ms + int((time.time() - _local_time_at_sync) * 1000)


# ─── HTTP helpers ──────────────────────────────────────────────────────────────


def signed_get(path: str, params: dict) -> dict | list:
    params["timestamp"] = now_ms()
    params["recvWindow"] = 10000
    query = urllib.parse.urlencode(params)
    signature = hmac.new(API_SECRET.encode(), query.encode(), hashlib.sha256).hexdigest()
    url = f"{BASE_URL}{path}?{query}&signature={signature}"
    req = urllib.request.Request(url, headers={"X-MBX-APIKEY": API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise RuntimeError(f"HTTP {e.code} for {path}: {body}")


def public_get(path: str, params: dict) -> dict | list:
    query = urllib.parse.urlencode(params)
    url = f"{BASE_URL}{path}?{query}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


# ─── Trade fetching ─────────────────────────────────────────────────────────────


def fetch_spot_trades(symbol: str) -> list[dict]:
    """GET /api/v3/myTrades — all spot trades for a symbol (paginated)."""
    all_trades: list[dict] = []
    from_id: int | None = None
    while True:
        params: dict[str, str | int] = {"symbol": symbol, "limit": 1000}
        if from_id is not None:
            params["fromId"] = from_id
        batch = signed_get("/api/v3/myTrades", params)
        if not batch:
            break
        all_trades.extend(batch)
        if len(batch) < 1000:
            break
        from_id = int(batch[-1]["id"]) + 1
    return all_trades


def fetch_margin_trades(symbol: str, is_isolated: bool) -> list[dict]:
    """GET /sapi/v1/margin/myTrades — margin trades for a symbol (paginated)."""
    all_trades: list[dict] = []
    from_id: int | None = None
    while True:
        params: dict[str, str | int | bool] = {
            "symbol": symbol,
            "isIsolated": str(is_isolated).lower(),
            "limit": 1000,
        }
        if from_id is not None:
            params["fromId"] = from_id
        batch = signed_get("/sapi/v1/margin/myTrades", params)
        if not batch:
            break
        all_trades.extend(batch)
        if len(batch) < 1000:
            break
        from_id = int(batch[-1]["id"]) + 1
    return all_trades


# ─── FIFO avg buy price computation ──────────────────────────────────────────


def fifo_avg_buy(trades: list[dict]) -> dict:
    """
    Compute weighted avg buy price using proper FIFO lot logic (mirrors the app).

    Steps:
      1. Sort all trades chronologically.
      2. Buys create BuyLot(price, qty - commission_if_base_asset).
      3. Sells consume earliest lots first (FIFO), reducing lot quantities.
      4. Weighted avg = Σ(lot.price * lot.remainingQty) / Σ(lot.remainingQty)
         over lots that still have remaining quantity.

    Returns dict with lot-level detail and summary stats.
    """
    # Sort by time
    sorted_trades = sorted(trades, key=lambda t: int(t.get("time", 0)))

    lots: list[dict] = []  # {price, remaining_qty}
    total_gross_invested = 0.0  # sum of (price * qty) for ALL buys, before commission
    total_buy_qty = 0.0
    total_sell_qty = 0.0
    total_commission = 0.0
    buy_count = 0
    sell_count = 0
    consumed_lots = 0

    for t in sorted_trades:
        qty = float(t.get("qty", 0))
        price = float(t.get("price", 0))
        commission = float(t.get("commission", 0))
        commission_asset = t.get("commissionAsset", "")

        if t.get("isBuyer", False):
            buy_count += 1
            total_buy_qty += qty
            total_gross_invested += price * qty
            net_qty = qty
            # Binance takes commission in the BASE asset (e.g. BTC for BTCUSDT).
            # Reduce lot quantity by the commission, and inflate lot price so that
            # lot.price * lot.remaining_qty covers the full USD spend including fees.
            if commission_asset == t.get("asset", ""):
                net_qty = qty - commission
                total_commission += commission
            if net_qty > 1e-12:
                if commission_asset == t.get("asset", ""):
                    lot_price = price * qty / net_qty
                    usdt_spent = price * qty
                elif commission_asset == "USDT" or commission > 0:
                    lot_price = (price * qty + commission) / net_qty
                    usdt_spent = price * qty + commission
                else:
                    lot_price = price
                    usdt_spent = price * qty
                lots.append({"price": lot_price, "remaining_qty": net_qty})
        else:
            sell_count += 1
            total_sell_qty += qty
            # FIFO consume
            remaining = qty
            while remaining > 1e-12 and lots:
                if lots[0]["remaining_qty"] <= remaining + 1e-12:
                    remaining -= lots[0]["remaining_qty"]
                    consumed_lots += 1
                    lots.pop(0)
                else:
                    lots[0]["remaining_qty"] -= remaining
                    remaining = 0

    # Compute weighted avg from remaining lots (FIFO-aware)
    total_invested = sum(l["price"] * l["remaining_qty"] for l in lots)
    total_remaining_qty = sum(l["remaining_qty"] for l in lots)
    weighted_avg = total_invested / total_remaining_qty if total_remaining_qty > 0 else 0.0

    # Naive avg: gross USD spent on ALL buys / gross qty bought (ignores sells, fees)
    naive_avg = total_gross_invested / total_buy_qty if total_buy_qty > 0 else 0.0

    return {
        "total_buy_qty": total_buy_qty,
        "total_sell_qty": total_sell_qty,
        "total_commission": total_commission,
        "gross_invested": total_gross_invested,
        "weighted_avg_fifo": weighted_avg,
        "naive_avg": naive_avg,
        "total_remaining_qty": total_remaining_qty,
        "remaining_lots": len(lots),
        "consumed_lots": consumed_lots,
        "trade_count": buy_count,
        "sell_count": sell_count,
        "lots": lots,
    }


def compute_avg_buy_per_mode(symbol: str, mode: str) -> dict:
    """Fetch trades for a mode and compute avg buy price."""
    if mode == "spot":
        trades = fetch_spot_trades(symbol)
        label = "Spot"
    elif mode == "cross":
        trades = fetch_margin_trades(symbol, is_isolated=False)
        label = "Cross-Margin"
    elif mode == "isolated":
        trades = fetch_margin_trades(symbol, is_isolated=True)
        label = "Isolated-Margin"
    else:
        raise ValueError(f"Unknown mode: {mode}")

    result = fifo_avg_buy(trades)
    result["mode"] = label
    result["raw_trade_count"] = len(trades)

    # Show individual buy trades (all, for debugging)
    buys = [t for t in trades if t.get("isBuyer", False)]
    sells = [t for t in trades if not t.get("isBuyer", False)]
    result["buys"] = buys
    result["sells"] = sells

    return result


# ─── Display ────────────────────────────────────────────────────────────────────


def print_result(symbol: str, r: dict) -> None:
    print(f"\n{'═' * 64}")
    print(f"  {r['mode']} — {symbol}")
    print(f"{'═' * 64}")
    print(f"  Raw trades fetched:    {r['raw_trade_count']}")
    print(f"  Buy trades:            {r['trade_count']}")
    print(f"  Sell trades:           {r['sell_count']}")
    print(f"  Total buy qty:         {r['total_buy_qty']:.8f}")
    print(f"  Total sell qty:        {r['total_sell_qty']:.8f}")
    print(f"  Total commission:      {r['total_commission']:.8f}")
    print(f"  Remaining qty:         {r['total_remaining_qty']:.8f}")
    print(f"  Lots consumed by FIFO: {r['consumed_lots']}")
    print(f"  Lots remaining:        {r['remaining_lots']}")
    print(f"  FIFO avg buy price:    {r['weighted_avg_fifo']:.6f}")
    print(f"  Naive avg (gross/qty): {r['naive_avg']:.6f}")
    print(f"{'─' * 64}")

    if r["buys"]:
        print(f"\n  Buy trades (sorted chronologically):")
        print(f"  {'#':<6} {'Price':>12} {'Qty':>14} {'Commission':>14} {'FeeAsset':>10} {'Time':>22}")
        print(f"  {'─' * 6} {'─' * 12} {'─' * 14} {'─' * 14} {'─' * 10} {'─' * 22}")
        for i, t in enumerate(r["buys"], 1):
            ts = time.strftime("%Y-%m-%d %H:%M", time.gmtime(int(t.get("time", 0)) / 1000))
            print(
                f"  {i:<6} {float(t['price']):>12.6f} {float(t['qty']):>14.8f} "
                f"{float(t.get('commission', 0)):>14.8f} {t.get('commissionAsset', ''):>10} "
                f"{ts:>22}"
            )

    if r["sells"]:
        print(f"\n  Sell trades:")
        print(f"  {'#':<6} {'Price':>12} {'Qty':>14} {'Time':>22}")
        print(f"  {'─' * 6} {'─' * 12} {'─' * 14} {'─' * 22}")
        for i, t in enumerate(r["sells"], 1):
            ts = time.strftime("%Y-%m-%d %H:%M", time.gmtime(int(t.get("time", 0)) / 1000))
            print(
                f"  {i:<6} {float(t['price']):>12.6f} {float(t['qty']):>14.8f} "
                f"{ts:>22}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit avg buy price from Binance API")
    parser.add_argument("symbol", help="Trading pair, e.g. XRPUSDT")
    parser.add_argument(
        "--mode",
        choices=["spot", "cross", "isolated", "all"],
        default="all",
        help="Trading mode (default: all)",
    )
    args = parser.parse_args()
    symbol = args.symbol.upper()

    print("=" * 64)
    print(f"  Avg Buy Price Audit — {symbol}")
    print("=" * 64)

    sync_clock()

    modes = ["spot", "cross", "isolated"] if args.mode == "all" else [args.mode]

    for mode in modes:
        try:
            r = compute_avg_buy_per_mode(symbol, mode)
            print_result(symbol, r)
        except Exception as e:
            print(f"\n  ⚠️  {mode}: {e}")

    # Show current price
    try:
        price_data = public_get("/api/v3/ticker/price", {"symbol": symbol})
        current = float(price_data["price"])
        print(f"\n{'═' * 64}")
        print(f"  Current market price: {current:.6f} USDT")
        print(f"{'═' * 64}")
    except Exception:
        pass

    print()


if __name__ == "__main__":
    main()
