#!/usr/bin/env python3
"""
FIFO daily profit validator — mirrors EasyCrypto's Trade History tab exactly.

Applies the same FIFO engine as Swift fifoComputeBreakdowns():
  - epsilon = 1.0 (dust filter)
  - Buy lots at raw trade.price (no base-asset commission inflation)
  - Fee-in-base-asset consumed from lot (not from proceeds)
  - USDT commission deducted from realized PnL

Usage:
  python3 scripts/validate_daily_profit.py trades.json
  python3 scripts/validate_daily_profit.py trades.json --asset BTC
  python3 scripts/validate_daily_profit.py trades.json --detail
  python3 scripts/validate_daily_profit.py --dump-app          # export from running app
"""

import json
import sys
import argparse
from datetime import datetime, timezone
from collections import defaultdict


# ── FIFO Engine (mirrors Swift fifoComputeBreakdowns) ─────────────────────────

def fifo_compute_breakdowns(trades):
    """
    Run FIFO over trades in chronological order.
    Returns list parallel to trades: None for buys, dict for sells.
    """
    epsilon = 1.0

    lots = []               # [{"price": float, "remaining": float}]
    breakdowns = []

    for trade in trades:
        if trade["isBuyer"]:
            qty = trade["quantity"]
            if trade["commissionAsset"] == trade["asset"]:
                qty -= trade["commission"]
            if qty > epsilon:
                lots.append({"price": trade["price"], "remaining": qty})
            breakdowns.append(None)

        else:
            fee_in_base = (trade["commissionAsset"] == trade["asset"]
                           and trade["commissionAsset"])
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

            cost_basis_price = cost_basis_amount / sold_quantity if sold_quantity > 0 else 0.0

            breakdowns.append({
                "costBasisPrice": round(cost_basis_price, 2),
                "costBasisAmount": round(cost_basis_amount, 4),
                "realizedPnL": round(sale_pnl, 4),
                "borrowingFee": borrowing_fee,
                "soldQuantity": sold_quantity,
            })

    return breakdowns


# ── I/O ──────────────────────────────────────────────────────────────────────

def load_trades(path, asset_filter=None):
    with open(path) as f:
        raw = json.load(f)

    trades = []
    for t in raw:
        trade = {
            "date": t.get("date", ""),
            "asset": t.get("asset", ""),
            "symbol": t.get("symbol", ""),
            "price": float(t["price"]),
            "quantity": float(t["quantity"]),
            "commission": float(t.get("commission", 0)),
            "commissionAsset": t.get("commissionAsset", t.get("commission_asset", "")),
            "isBuyer": bool(t["isBuyer"]),
            "quoteQuantity": float(t.get("quoteQuantity", t.get("quote_quantity", 0))),
            "tradingMode": t.get("tradingMode", t.get("trading_mode", "spot")),
            "timestamp": t.get("timestamp", t.get("time", "")),
        }
        if "borrowingFee" in t:
            trade["borrowingFee"] = float(t["borrowingFee"])
        trades.append(trade)

    trades.sort(key=lambda t: t["date"])

    if asset_filter:
        trades = [t for t in trades if t["asset"] == asset_filter]

    return trades


def dump_from_app():
    """
    Prompt the user to paste JSON from the app.
    The app can export trades via: Settings → Export, or via a debug dump.
    Expected: array of trade objects matching the Trade model fields.
    """
    print("Paste your trades JSON array (Ctrl+D when done):")
    raw = sys.stdin.read()
    data = json.loads(raw)
    # Save to a temp file for re-use
    out = "/tmp/easycrypto_trades_dump.json"
    with open(out, "w") as f:
        json.dump(data, f, indent=2)
    print(f"\nSaved {len(data)} trades to {out}")
    return data


# ── Reporting ─────────────────────────────────────────────────────────────────

def print_daily_profit(breakdowns, trades):
    """Mirrors Trade History tab: one row per calendar day."""
    daily = defaultdict(lambda: {
        "sellCount": 0, "tradeCount": 0,
        "costBasis": 0.0, "pnl": 0.0, "borrowingFee": 0.0,
        "buyQty": 0.0, "sellQty": 0.0,
    })

    for trade, bd in zip(trades, breakdowns):
        day = trade["date"][:10] if len(trade["date"]) >= 10 else trade["date"]
        d = daily[day]
        d["tradeCount"] += 1

        if trade["isBuyer"]:
            d["buyQty"] += trade["quantity"]
        else:
            d["sellCount"] += 1
            d["sellQty"] += trade["quantity"]
            if bd:
                d["costBasis"] += bd["costBasisAmount"]
                d["pnl"] += bd["realizedPnL"]
                d["borrowingFee"] += bd["borrowingFee"]

    # Header matching app layout
    print(f"\n{'Date':<14} {'Buys':>5} {'Sells':>5} {'Cost Basis':>12} {'Realized PnL':>14} {'Borrow Fee':>11}")
    print("─" * 65)

    total_pnl = 0.0
    for day in sorted(daily):
        d = daily[day]
        total_pnl += d["pnl"]
        pnl_str = f"+{d['pnl']:>10.2f}" if d["pnl"] >= 0 else f"{d['pnl']:>11.2f}"
        print(
            f"{day:<14} {d['buyQty']:>5.2f} {d['sellQty']:>5.2f} "
            f"{d['costBasis']:>12.2f} {pnl_str} {d['borrowingFee']:>11.4f}"
        )

    print("─" * 65)
    total_str = f"+{total_pnl:>10.2f}" if total_pnl >= 0 else f"{total_pnl:>11.2f}"
    print(f"{'TOTAL':<14} {'':>5} {'':>5} {'':>12} {total_str}")


def print_detail(breakdowns, trades):
    """Line-by-line: every trade with its breakdown (sells show PnL)."""
    print(f"\n{'#':>4} {'Date':<12} {'Side':>4} {'Asset':<8} {'Price':>10} {'Qty':>10} {'Comm':>8} {'Pnl':>12}")
    print("─" * 80)

    for i, (trade, bd) in enumerate(zip(trades, breakdowns), 1):
        side = "BUY" if trade["isBuyer"] else "SELL"
        if bd:
            pnl_str = f"+{bd['realizedPnL']:>10.2f}" if bd["realizedPnL"] >= 0 else f"{bd['realizedPnL']:>11.2f}"
        else:
            pnl_str = f"{'—':>12}"
        comm = f"{trade['commission']:.6f}" if trade["commission"] > 0 else "0"
        date_str = trade["date"][:10] if len(trade["date"]) >= 10 else trade["date"]
        print(
            f"{i:>4} {date_str:<12} {side:>4} {trade['asset']:<8} "
            f"{trade['price']:>10.2f} {trade['quantity']:>10.6f} {comm:>8} {pnl_str}"
        )


def print_month_summary(breakdowns, trades):
    """Group by YYYY-MM like the Trade History month summary bar."""
    monthly = defaultdict(lambda: {"pnl": 0.0, "sells": 0})
    for trade, bd in zip(trades, breakdowns):
        if not trade["isBuyer"] and bd:
            month = trade["date"][:7]
            monthly[month]["pnl"] += bd["realizedPnL"]
            monthly[month]["sells"] += 1

    print(f"\n{'Month':<10} {'Sells':>6} {'Realized PnL':>14}")
    print("─" * 32)
    total = 0.0
    for month in sorted(monthly):
        m = monthly[month]
        total += m["pnl"]
        pnl_str = f"+{m['pnl']:>10.2f}" if m["pnl"] >= 0 else f"{m['pnl']:>11.2f}"
        print(f"{month:<10} {m['sells']:>6} {pnl_str}")
    print("─" * 32)


# ── Main ──────────────────────────────────────────────────────────────────────

def fetch_trades_for_date(date_str):
    """
    Run binance-july-trades.sh via subprocess (once, into a temp dir),
    then load the JSON file for the given date.
    Returns (trades_list, output_dir).
    """
    import subprocess, tempfile, os, sys
    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "binance-july-trades.sh")
    if not os.path.exists(script_path):
        print(f"ERROR: {script_path} not found.", file=sys.stderr)
        sys.exit(1)
    out_dir = tempfile.mkdtemp(prefix="easycrypto_trades_")
    date_file = os.path.join(out_dir, f"{date_str}.json")
    print(f"Fetching trades for {date_str}…")
    try:
        result = subprocess.run(
            ["bash", script_path, out_dir],
            capture_output=True, text=True, timeout=300,
            env={**os.environ, "PYTHONUNBUFFERED": "1"}
        )
        if result.returncode != 0:
            print(f"ERROR: bash script failed (exit {result.returncode}):", file=sys.stderr)
            print(result.stderr[-500:] if result.stderr else "", file=sys.stderr)
            sys.exit(1)
    except FileNotFoundError:
        print("ERROR: bash not found.", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("ERROR: fetch timed out (300s).", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(date_file):
        print(f"ERROR: expected {date_file} not found. No trades for {date_str}?", file=sys.stderr)
        print("Files produced:", os.listdir(out_dir), file=sys.stderr)
        sys.exit(1)
    with open(date_file) as f:
        raw = json.load(f)
    return raw, out_dir


def main():
    parser = argparse.ArgumentParser(
        description="Validate Trade History daily profit against the app"
    )
    parser.add_argument("file", nargs="?", help="JSON file with trade array")
    parser.add_argument("--asset", help="Filter to one asset (e.g. BTC)")
    parser.add_argument("--detail", action="store_true", help="Print every trade with PnL")
    parser.add_argument("--month", action="store_true", help="Show month summary")
    parser.add_argument("--dump", action="store_true", help="Read JSON from stdin (paste from app)")
    parser.add_argument("--date", metavar="YYYY-MM-DD",
                        help="Fetch Binance trades for a date via binance-july-trades.sh "
                             "(requires BINANCE_API_KEY and BINANCE_API_SECRET env vars)")
    args = parser.parse_args()

    # Load trades
    if args.date:
        raw, _out_dir = fetch_trades_for_date(args.date)
        trades = load_trades_from_list(raw)
    elif args.dump:
        data = dump_from_app()
        trades = load_trades_from_list(data)
    elif args.file:
        trades = load_trades(args.file)
    else:
        parser.print_help()
        sys.exit(1)

    if args.asset:
        trades = [t for t in trades if t["asset"] == args.asset]

    if not trades:
        print("No trades found.", file=sys.stderr)
        sys.exit(1)

    breakdowns = fifo_compute_breakdowns(trades)

    if args.detail:
        print_detail(breakdowns, trades)

    if args.month:
        print_month_summary(breakdowns, trades)

    print_daily_profit(breakdowns, trades)


def load_trades_from_list(raw):
    """Load from already-parsed JSON list (for --dump mode)."""
    trades = []
    for t in raw:
        trade = {
            "date": t.get("date", ""),
            "asset": t.get("asset", ""),
            "symbol": t.get("symbol", ""),
            "price": float(t["price"]),
            "quantity": float(t["quantity"]),
            "commission": float(t.get("commission", 0)),
            "commissionAsset": t.get("commissionAsset", t.get("commission_asset", "")),
            "isBuyer": bool(t["isBuyer"]),
            "quoteQuantity": float(t.get("quoteQuantity", t.get("quote_quantity", 0))),
            "tradingMode": t.get("tradingMode", t.get("trading_mode", "spot")),
        }
        if "borrowingFee" in t:
            trade["borrowingFee"] = float(t["borrowingFee"])
        trades.append(trade)
    trades.sort(key=lambda t: t["date"])
    return trades


if __name__ == "__main__":
    main()
