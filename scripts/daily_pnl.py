#!/usr/bin/env python3
"""
Daily P&L Report — Show all trades and realized P&L for a specific date.

Usage:
    python daily_pnl.py 2026-09-12
    python daily_pnl.py 2026-08-20
"""

import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Literal


# CSV column indices (0-based)
COL_TIME = 0
COL_ORDER_NO = 1
COL_PAIR = 2
COL_TYPE = 3
COL_SIDE = 4
COL_ORDER_PRICE = 5
COL_ORDER_AMT = 6
COL_EXEC_TIME = 7
COL_EXEC_QTY = 8
COL_AVG_PRICE = 9
COL_TOTAL = 10
COL_STATUS = 11


@dataclass
class Trade:
    dt: datetime
    mode: Literal["Spot", "Cross Margin", "Isolated Margin"]
    order_no: str
    pair: str
    side: Literal["BUY", "SELL"]
    qty: float
    avg_price: float
    total: float
    asset: str


@dataclass
class Lot:
    dt: datetime
    price: float
    qty: float


def extract_asset(pair: str) -> str:
    """Extract base asset from pair like 'BTCUSDT' → 'BTC'."""
    for quote in ("USDT", "USDC", "BUSD", "USD"):
        if pair.endswith(quote):
            return pair[: -len(quote)]
    return pair


def parse_amount(s: str) -> float:
    """Parse '1000.5USDT' or '1000.5' → 1000.5."""
    s = s.strip()
    for suffix in ("USDT", "USDC", "BUSD", "BTC", "ETH", "BNB", "SOL", "XRP",
                   "DEXE", "MMT", "BANK", "NEAR", "LTC", "IOTA", "ALLO",
                   "HYPER", "SENT", "TRX", "ADA", "BCH", "UNI", "MET",
                   "IOTX", "ACE", "AED", "TON"):
        if s.endswith(suffix):
            s = s[: -len(suffix)]
            break
    return float(s) if s else 0.0


def parse_dt(s: str) -> datetime:
    """Parse datetime from CSV (handles multiple formats)."""
    s = s.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%d/%m/%Y %H:%M"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    raise ValueError(f"Cannot parse datetime: {s}")


def read_trades(csv_path: Path, mode_name: str, target_date: str) -> list[Trade]:
    """Read trades from CSV file for a specific date."""
    if not csv_path.exists():
        return []

    trades: list[Trade] = []
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
                dt = parse_dt(row[COL_TIME])
                if dt.strftime("%Y-%m-%d") != target_date:
                    continue

                asset = extract_asset(row[COL_PAIR].strip())
                qty = parse_amount(row[COL_EXEC_QTY])
                total = parse_amount(row[COL_TOTAL])
                avg_price = total / qty if qty > 1e-12 else 0

                trades.append(Trade(
                    dt=dt,
                    mode=mode_name,
                    order_no=row[COL_ORDER_NO].strip(),
                    pair=row[COL_PAIR].strip(),
                    side=side,
                    qty=qty,
                    avg_price=avg_price,
                    total=total,
                    asset=asset,
                ))
            except (ValueError, KeyError, IndexError):
                continue

    return trades


def compute_fifo_pnl(trades: list[Trade]) -> dict[str, float]:
    """
    Compute FIFO realized P&L per asset for given trades.
    Returns dict of asset → realized P&L.
    """
    lots_by_asset: dict[str, list[Lot]] = defaultdict(list)
    pnl_by_asset: dict[str, float] = defaultdict(float)

    for trade in sorted(trades, key=lambda t: t.dt):
        lots = lots_by_asset[trade.asset]

        if trade.side == "BUY":
            lots.append(Lot(dt=trade.dt, price=trade.avg_price, qty=trade.qty))
        else:  # SELL
            remaining = trade.qty
            proceeds = trade.total

            while remaining > 1e-12 and lots:
                lot = lots[0]
                consumed = min(lot.qty, remaining)
                cost = consumed * lot.price
                pnl_by_asset[trade.asset] += proceeds * (consumed / trade.qty) - cost

                lot.qty -= consumed
                remaining -= consumed
                if lot.qty < 1e-12:
                    lots.pop(0)

    return pnl_by_asset


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python daily_pnl.py YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    target_date = sys.argv[1]
    try:
        datetime.strptime(target_date, "%Y-%m-%d")
    except ValueError:
        print(f"Invalid date format: {target_date}. Use YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    data_dir = Path(__file__).parent.parent / "data"
    csv_files = [
        ("Spot", data_dir / "Binance-Spot-Order-History-202609120528(UTC+4)-part1-of1.csv"),
        ("Cross Margin", data_dir / "Binance-Margin-Order-History-202609120532(UTC+4)-cross.csv"),
        ("Isolated Margin", data_dir / "Binance-Margin-Order-History-202609120532(UTC+4)-isolated.csv"),
    ]

    # ── Read all trades for target date ────────────────────────────────────
    all_trades: list[Trade] = []
    for mode_name, csv_path in csv_files:
        trades = read_trades(csv_path, mode_name, target_date)
        all_trades.extend(trades)

    if not all_trades:
        print(f"No filled trades found for {target_date}")
        sys.exit(0)

    # Sort by time
    all_trades.sort(key=lambda t: t.dt)

    # ── Compute P&L ────────────────────────────────────────────────────────
    pnl_by_asset = compute_fifo_pnl(all_trades)
    total_pnl = sum(pnl_by_asset.values())

    # ── Output ─────────────────────────────────────────────────────────────
    print("=" * 70)
    print(f"  DAILY P&L REPORT  ·  {target_date}")
    print("=" * 70)
    print()

    # Show all trades
    print(f"  Total Trades: {len(all_trades)}")
    print()
    print("  Timestamp            Mode              Side   Asset      Qty          Price        Total")
    print("  " + "-" * 96)

    for t in all_trades:
        mode_label = f"{t.mode:16}"
        side_label = "🟢 BUY " if t.side == "BUY" else "🔴 SELL"
        print(f"  {t.dt.strftime('%Y-%m-%d %H:%M:%S')}  {mode_label}  {side_label}  "
              f"{t.asset:8}  {t.qty:>12.4f}  {t.avg_price:>10.4f}  {t.total:>12.2f} USDT")

    print()
    print("=" * 70)
    print(f"  REALIZED P&L (FIFO)")
    print("=" * 70)
    print()

    if pnl_by_asset:
        sorted_assets = sorted(pnl_by_asset.items(), key=lambda x: x[1])
        for asset, pnl in sorted_assets:
            symbol = "▼" if pnl < 0 else "▲"
            print(f"    {asset:10}  {symbol}  {pnl:>12.2f} USDT")
        print()

    print("  " + "-" * 66)
    symbol = "▼" if total_pnl < 0 else "▲"
    print(f"  TOTAL      {symbol}  {total_pnl:>12.2f} USDT")
    print("=" * 70)


if __name__ == "__main__":
    main()
