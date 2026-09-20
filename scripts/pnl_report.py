#!/usr/bin/env python3
"""
FIFO P&L calculator for Binance Spot Order History CSV.

Reads the exported order history, matches sells against buys using FIFO,
and prints:
  - total realized P&L
  - P&L per asset
  - P&L per month
  - P&L per day
"""

import csv
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# ── CSV column positions (header has duplicate "Time", so we use indexes) ───
COL_TIME       = 0   # order date/time  (e.g. "09/09/2026 22:06")
COL_PAIR       = 2   # e.g. "BTCUSDT"
COL_SIDE       = 4   # "BUY" or "SELL"
COL_ORDER_PX   = 5   # order price (string)
COL_ORDER_AMT  = 6   # order amount with unit  e.g. "0.04843BTC"
COL_EXEC_DT    = 7   # execution date/time
COL_EXEC_QTY   = 8   # executed qty with unit   e.g. "0.04843BTC"
COL_AVG_PX     = 9   # average fill price
COL_TOTAL      = 10  # trading total with unit  e.g. "3782.383USDT"
COL_STATUS     = 11  # "FILLED" etc.


# ── helpers ───────────────────────────────────────────────────────────────────

def extract_asset(pair: str) -> str:
    """BTCUSDT → BTC, ETHUSDT → ETH, etc."""
    return pair.replace("USDT", "").replace("BUSD", "")


def parse_amount(raw: str) -> float:
    """Strip unit suffix: '0.04843BTC' → 0.04843"""
    return float("".join(c for c in raw if c.isdigit() or c == "." or c == "-"))


def parse_dt(raw: str) -> datetime:
    """Parse datetime from Binance CSV formats."""
    raw = raw.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%d/%m/%Y %H:%M", "%m/%d/%Y %H:%M"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue
    raise ValueError(f"Unrecognized date format: {raw!r}")


# ── FIFO engine ───────────────────────────────────────────────────────────────

class Lot:
    __slots__ = ("qty", "price", "dt")
    def __init__(self, qty: float, price: float, dt):
        self.qty = qty
        self.price = price
        self.dt = dt


def fifo_realized_pnl(trades: list[dict]) -> tuple[float, list[dict]]:
    """
    Run FIFO on a chronologically-sorted list of trades for one asset.
    Returns (total_realized_pnl, per_sell_breakdown).
    """
    lots: list[Lot] = []
    total_pnl = 0.0
    eps = 1e-12
    breakdowns: list[dict] = []

    for t in trades:
        if t["side"] == "BUY":
            qty = t["qty"]
            price = t["avg_price"]
            if qty > eps:
                lots.append(Lot(qty, price, t["dt"]))
        else:  # SELL
            sell_qty = t["qty"]
            sell_price = t["avg_price"]
            sell_dt = t["dt"]
            pnl = 0.0
            while sell_qty > eps and lots:
                consumed = min(lots[0].qty, sell_qty)
                pnl += consumed * (sell_price - lots[0].price)
                lots[0].qty -= consumed
                sell_qty -= consumed
                if lots[0].qty <= eps:
                    lots.pop(0)
            total_pnl += pnl
            if pnl != 0 or sell_qty > eps:
                breakdowns.append({
                    "date": sell_dt,
                    "side": "SELL",
                    "qty": t["qty"],
                    "price": sell_price,
                    "total": t["total"],
                    "pnl": pnl,
                })

    return total_pnl, breakdowns


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    data_dir = Path(__file__).parent.parent / "data"
    csv_files = [
        ("Spot", data_dir / "Binance-Spot-Order-History-202609120528(UTC+4)-part1-of1.csv"),
        ("Cross Margin", data_dir / "Binance-Margin-Order-History-202609120532(UTC+4)-cross.csv"),
        ("Isolated Margin", data_dir / "Binance-Margin-Order-History-202609120532(UTC+4)-isolated.csv"),
    ]

    # ── read & group by asset ──────────────────────────────────────────────
    raw_trades: dict[str, list[dict]] = defaultdict(list)

    for mode_name, csv_path in csv_files:
        if not csv_path.exists():
            print(f"Warning: {mode_name} CSV not found: {csv_path}", file=sys.stderr)
            continue

        with open(csv_path, newline="", encoding="utf-8-sig") as fh:
            reader = csv.reader(fh)
            next(reader)  # skip header
            for row in reader:
                if len(row) <= COL_STATUS:
                    continue
                if row[COL_STATUS].strip().upper() != "FILLED":
                    continue
                side = row[COL_SIDE].strip().upper()
                if side not in ("BUY", "SELL"):
                    continue
                try:
                    asset = extract_asset(row[COL_PAIR].strip())
                    qty = parse_amount(row[COL_EXEC_QTY])
                    total = parse_amount(row[COL_TOTAL])
                    dt = parse_dt(row[COL_TIME])
                except (ValueError, KeyError, IndexError):
                    continue

                raw_trades[asset].append({
                    "side": side,
                    "qty": qty,
                    "avg_price": total / qty if qty > 1e-12 else 0,
                    "total": total,
                    "dt": dt,
                })

    # sort each asset chronologically
    for trades in raw_trades.values():
        trades.sort(key=lambda t: t["dt"])

    # ── FIFO per asset ────────────────────────────────────────────────────
    total_pnl = 0.0
    per_month: dict[str, float] = defaultdict(float)
    per_day: dict[str, float] = defaultdict(float)
    per_asset: dict[str, float] = {}

    for asset, trades in sorted(raw_trades.items()):
        pnl, breakdowns = fifo_realized_pnl(trades)
        per_asset[asset] = pnl
        total_pnl += pnl

        for b in breakdowns:
            if b["pnl"] == 0:
                continue
            m_key = b["date"].strftime("%Y-%m")
            d_key = b["date"].strftime("%Y-%m-%d")
            per_month[m_key] += b["pnl"]
            per_day[d_key] += b["pnl"]

    # ── report ────────────────────────────────────────────────────────────
    W = 60
    print("=" * W)
    print("  FIFO REALIZED P&L  ·  Binance Spot")
    print("=" * W)

    print(f"\n{'TOTAL REALIZED P&L':>40}  {total_pnl:>12,.2f} USDT\n")

    print("  Per Asset")
    print("  " + "-" * (W - 2))
    for asset, pnl in sorted(per_asset.items(), key=lambda x: x[1]):
        flag = "▲" if pnl >= 0 else "▼"
        print(f"    {asset:<8} {flag} {pnl:>+12,.2f} USDT")

    print("\n  Per Month")
    print("  " + "-" * (W - 2))
    for m in sorted(per_month):
        pnl = per_month[m]
        flag = "▲" if pnl >= 0 else "▼"
        print(f"    {m}  {flag} {pnl:>+12,.2f} USDT")

    print("\n  Per Day  (showing days with P&L)")
    print("  " + "-" * (W - 2))
    for d in sorted(per_day):
        pnl = per_day[d]
        flag = "▲" if pnl >= 0 else "▼"
        print(f"    {d}  {flag} {pnl:>+12,.2f} USDT")

    print("\n" + "=" * W)


if __name__ == "__main__":
    main()
