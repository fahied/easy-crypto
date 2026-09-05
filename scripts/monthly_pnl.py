#!/usr/bin/env python3
"""
Monthly P&L view — aggregates the per-day JSON files produced by binance-july-trades.sh
into a month-by-month summary of realized P&L, sells, and volume.

Usage:
  python3 scripts/monthly_pnl.py [trades_dir]

  trades_dir  Directory of daily JSON files (default: ./binance-trades-july2026)

Output:
  Per-month table: date range, # sells, realized PnL, volume, net PnL (after fees)
  Plus a grand-total row.

The FIFO engine mirrors EasyCrypto's Swift fifoComputeBreakdowns() exactly:
  - epsilon = 1.0 dust filter
  - Buy lots inflated when commission is in base asset
  - Fee-in-base-asset consumed from lot (not from proceeds)
  - USDT commission deducted from realized PnL
"""

import json
import sys
import os
import argparse
from collections import defaultdict
from datetime import datetime


# ── FIFO Engine (mirrors Swift fifoComputeBreakdowns) ─────────────────────────

def fifo_compute_breakdowns(trades):
    """Run FIFO over trades in chronological order. Returns per-trade breakdowns."""
    epsilon = 1.0
    lots = []
    breakdowns = []

    for trade in trades:
        if trade["isBuyer"]:
            qty = trade["quantity"]
            if trade["commissionAsset"] == trade["asset"]:
                qty -= trade["commission"]
            if qty > epsilon:
                if trade["commissionAsset"] == trade["asset"]:
                    lot_price = trade["price"] * trade["quantity"] / qty
                elif trade["commissionAsset"] == "USDT" or trade["commission"] > 0:
                    lot_price = (trade["price"] * trade["quantity"] + trade["commission"]) / qty
                else:
                    lot_price = trade["price"]
                lots.append({"price": lot_price, "remaining": qty})
            breakdowns.append(None)

        else:
            fee_in_base = trade["commissionAsset"] == trade["asset"] and trade["commissionAsset"]
            fee_amount = trade["commission"] if fee_in_base else 0.0

            sell_qty = trade["quantity"] + fee_amount
            remaining_sell_qty = trade["quantity"]

            sale_pnl = 0.0
            sold_quantity = 0.0
            cost_basis_amount = 0.0

            while sell_qty > 0 and lots:
                consumed = min(lots[0]["remaining"], sell_qty)
                sold_portions = min(consumed, remaining_sell_qty)
                fee_portion = consumed - sold_portions

                sale_pnl += sold_portions * (trade["price"] - lots[0]["price"])
                sale_pnl -= fee_portion * lots[0]["price"]

                sold_quantity += sold_portions
                cost_basis_amount += sold_portions * lots[0]["price"]

                lots[0]["remaining"] -= consumed
                sell_qty -= consumed
                remaining_sell_qty -= sold_portions

                if lots[0]["remaining"] <= epsilon:
                    lots.pop(0)

            if trade.get("commissionAsset") == "USDT":
                sale_pnl -= trade["commission"]

            borrowing_fee = trade.get("borrowingFee", 0.0)
            sale_pnl -= borrowing_fee

            breakdowns.append({
                "realizedPnL": round(sale_pnl, 4),
                "borrowingFee": borrowing_fee,
                "soldQuantity": sold_quantity,
                "costBasisAmount": round(cost_basis_amount, 4),
            })

    return breakdowns


# ── I/O ────────────────────────────────────────────────────────────────────────

def load_daily_file(path):
    """Load and normalize a single day's JSON file."""
    with open(path) as f:
        raw = json.load(f)

    trades = []
    for t in raw:
        trade = {
            "date": t.get("date", ""),
            "asset": t.get("asset", ""),
            "price": float(t["price"]),
            "quantity": float(t["quantity"]),
            "commission": float(t.get("commission", 0)),
            "commissionAsset": t.get("commissionAsset", ""),
            "isBuyer": bool(t["isBuyer"]),
            "tradingMode": t.get("tradingMode", "spot"),
        }
        if "borrowingFee" in t:
            trade["borrowingFee"] = float(t["borrowingFee"])
        trades.append(trade)

    trades.sort(key=lambda t: t["date"])
    return trades


def load_trades_dir(directory):
    """Load all daily JSON files from a directory, sorted chronologically."""
    if not os.path.isdir(directory):
        print(f"ERROR: {directory} is not a directory.", file=sys.stderr)
        sys.exit(1)

    files = sorted([
        f for f in os.listdir(directory)
        if f.endswith(".json") and os.path.isfile(os.path.join(directory, f))
    ])

    if not files:
        print(f"ERROR: No .json files found in {directory}.", file=sys.stderr)
        sys.exit(1)

    all_trades = []
    skipped = 0
    for fname in files:
        path = os.path.join(directory, fname)
        try:
            day_trades = load_daily_file(path)
            all_trades.extend(day_trades)
        except (json.JSONDecodeError, KeyError) as e:
            print(f"  ⚠ Skipping {fname}: {e}", file=sys.stderr)
            skipped += 1

    if skipped:
        print(f"  Skipped {skipped} file(s) with errors.", file=sys.stderr)

    all_trades.sort(key=lambda t: t["date"])
    return all_trades


# ── Formatting ─────────────────────────────────────────────────────────────────

def fmt_usdt(value):
    """Format a USDT value with sign and thousands separator."""
    if value >= 0:
        return f"+{value:>10,.2f}"
    return f"{value:>11,.2f}"


def fmt_pct(value):
    """Format a percentage with sign."""
    if value >= 0:
        return f"+{value:.2f}%"
    return f"{value:.2f}%"


# ── Monthly Report ─────────────────────────────────────────────────────────────

def print_monthly_pnl(breakdowns, trades):
    """
    Group realized PnL by month (YYYY-MM) across all assets.
    Mirrors the per-day granularity but rolls it up per calendar month.
    """
    monthly = defaultdict(lambda: {
        "sellCount": 0,
        "realizedPnL": 0.0,
        "borrowingFee": 0.0,
        "costBasis": 0.0,
        "volume": 0.0,
        "buyQty": 0.0,
        "sellQty": 0.0,
        "days": set(),
    })

    for trade, bd in zip(trades, breakdowns):
        month = trade["date"][:7]  # "YYYY-MM"
        day = trade["date"][:10]
        m = monthly[month]

        m["tradeCount"] = m.get("tradeCount", 0) + 1
        m["days"].add(day)

        if trade["isBuyer"]:
            m["buyQty"] += trade["quantity"]
        else:
            m["sellCount"] += 1
            m["sellQty"] += trade["quantity"]
            m["volume"] += trade.get("quoteQuantity", trade["price"] * trade["quantity"])
            if bd:
                m["realizedPnL"] += bd["realizedPnL"]
                m["borrowingFee"] += bd["borrowingFee"]
                m["costBasis"] += bd["costBasisAmount"]

    # Compute net PnL (realized minus fees)
    for m in monthly.values():
        m["netPnL"] = m["realizedPnL"] - m["borrowingFee"]

    # Derive month labels (YYYY-MM) and sort
    months = sorted(monthly.keys())

    # ── Header ─────────────────────────────────────────────────────────────
    print()
    print("=" * 90)
    print(f"  {'Month':<10}  {'Days':>5}  {'Sells':>6}  {'Buy Vol':>12}  {'Sell Vol':>12}  "
          f"{'Cost Basis':>12}  {'Net PnL':>12}  {'Return%':>9}")
    print("─" * 90)

    total_pnl = 0.0
    total_buy_vol = 0.0
    total_sell_vol = 0.0
    total_cost = 0.0
    total_sells = 0
    total_days = set()

    for month in months:
        m = monthly[month]
        total_pnl += m["netPnL"]
        total_buy_vol += m["buyQty"]
        total_sell_vol += m["sellQty"]
        total_cost += m["costBasis"]
        total_sells += m["sellCount"]
        total_days.update(m["days"])

        # Return% = netPnL / costBasis
        if m["costBasis"] > 0:
            ret = (m["netPnL"] / m["costBasis"]) * 100
        else:
            ret = 0.0

        # Month label: "YYYY-MM"
        label = month

        pnl_str = fmt_usdt(m["netPnL"])
        ret_str = fmt_pct(ret)

        print(
            f"  {label:<10}  {len(m['days']):>5}  {m['sellCount']:>6}  "
            f"{m['buyQty']:>12.4f}  {m['sellQty']:>12.4f}  "
            f"{m['costBasis']:>12.2f}  {pnl_str}  {ret_str:>9}"
        )

    # ── Totals ──────────────────────────────────────────────────────────────
    print("─" * 90)

    total_ret = (total_pnl / total_cost * 100) if total_cost > 0 else 0.0
    total_pnl_str = fmt_usdt(total_pnl)
    total_ret_str = fmt_pct(total_ret)

    print(
        f"  {'TOTAL':<10}  {len(total_days):>5}  {total_sells:>6}  "
        f"{total_buy_vol:>12.4f}  {total_sell_vol:>12.4f}  "
        f"{total_cost:>12.2f}  {total_pnl_str}  {total_ret_str:>9}"
    )
    print("=" * 90)
    print()


def print_monthly_by_asset(breakdowns, trades):
    """
    Per-month, per-asset breakdown — shows which assets drove the PnL.
    """
    # Aggregate per (month, asset)
    monthly_asset = defaultdict(lambda: {
        "sellCount": 0,
        "realizedPnL": 0.0,
        "borrowingFee": 0.0,
        "costBasis": 0.0,
        "sellQty": 0.0,
    })

    for trade, bd in zip(trades, breakdowns):
        if trade["isBuyer"]:
            continue
        month = trade["date"][:7]
        asset = trade["asset"]
        ma = monthly_asset[(month, asset)]
        ma["sellCount"] += 1
        ma["sellQty"] += trade["quantity"]
        if bd:
            ma["realizedPnL"] += bd["realizedPnL"]
            ma["borrowingFee"] += bd["borrowingFee"]
            ma["costBasis"] += bd["costBasisAmount"]

    # Group by month
    by_month = defaultdict(dict)
    for (month, asset), data in monthly_asset.items():
        data["netPnL"] = data["realizedPnL"] - data["borrowingFee"]
        by_month[month][asset] = data

    months = sorted(by_month.keys())

    print()
    print("=" * 70)
    print("  Monthly P&L by Asset")
    print("=" * 70)

    for month in months:
        assets = by_month[month]
        print(f"\n  {month}")
        print(f"  {'Asset':<10}  {'Sells':>6}  {'Qty':>10}  {'Cost Basis':>12}  {'Net PnL':>12}")
        print("  " + "─" * 58)

        month_pnl = 0.0
        for asset in sorted(assets.keys()):
            a = assets[asset]
            month_pnl += a["netPnL"]
            pnl_str = fmt_usdt(a["netPnL"])
            print(
                f"  {asset:<10}  {a['sellCount']:>6}  {a['sellQty']:>10.4f}  "
                f"{a['costBasis']:>12.2f}  {pnl_str}"
            )

        print("  " + "─" * 58)
        print(f"  {'Month Total':<10}  {'':>6}  {'':>10}  {'':>12}  {fmt_usdt(month_pnl)}")

    print()
    print("=" * 70)
    print()


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Monthly view of daily P&L from Binance trade history"
    )
    parser.add_argument(
        "directory", nargs="?", default="./binance-trades-july2026",
        help="Directory of daily JSON files (default: ./binance-trades-july2026)"
    )
    parser.add_argument(
        "--by-asset", action="store_true",
        help="Show per-month, per-asset breakdown"
    )
    args = parser.parse_args()

    print(f"Loading trades from {args.directory} …")
    trades = load_trades_dir(args.directory)
    print(f"  {len(trades)} trades loaded.")

    if not trades:
        print("No trades to process.", file=sys.stderr)
        sys.exit(0)

    # Date range
    dates = [t["date"][:10] for t in trades]
    print(f"  Date range: {dates[0]} → {dates[-1]}")
    print(f"  Running FIFO …")

    breakdowns = fifo_compute_breakdowns(trades)
    sells = sum(1 for bd in breakdowns if bd is not None)
    print(f"  {sells} sell trades processed.")

    print_monthly_pnl(breakdowns, trades)

    if args.by_asset:
        print_monthly_by_asset(breakdowns, trades)


if __name__ == "__main__":
    main()
