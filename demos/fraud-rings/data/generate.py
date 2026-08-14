#!/usr/bin/env python3
"""Generate a synthetic P2P payments dataset with planted fraud rings.

Why synthetic: payment data is among the most sensitive an organisation holds,
so a public example repo cannot ship it and should not ask you to point a first
run at production. The shape here mirrors what a real P2P ledger looks like —
accounts, the devices they sign in from, transfers between them, merchant
payments — so the graph model and every query transfer to real data unchanged.

Deterministic: same seed, same graph, including the rings the queries find.

Emits Spanner DML. Rows are batched into multi-row INSERT statements because
Spanner caps mutations per commit, and one statement per row would take minutes
rather than seconds.
"""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import random

# The signal this demo is built around. A device shared by a handful of
# accounts that then move money between themselves is the classic ring shape:
# each account looks unremarkable alone, and the pattern only exists in the
# relationships.
FINDINGS = """
Planted findings — what the demo's queries should surface:

  1. RING-A: 4 accounts share one device and move funds in a closed cycle,
     returning most of it to where it started. No single account looks odd.

  2. RING-B: 3 accounts share a device and fan money OUT to one collector
     account that then pays a single merchant. A mule pattern.

  3. One legitimate shared device (a family) with 3 accounts and NO money
     movement between them — the false positive a device-only rule would flag
     and a graph query correctly ignores.
"""

FIRST = ["ana", "ben", "cleo", "dev", "elif", "femi", "gus", "hana", "ivan",
         "jo", "kai", "lena", "milo", "nadia", "omar", "pia", "quinn", "rosa",
         "sam", "tariq", "uma", "vic", "wren", "xan", "yuri", "zoe"]
LAST = ["acuna", "brandt", "cole", "diallo", "esposito", "fontaine", "gupta",
        "haddad", "ionescu", "jensen", "kovac", "lindqvist", "moreau",
        "nakamura", "okafor", "petrov", "reyes", "silva", "tanaka", "ustinov"]
# Paired with their category — an earlier version drew categories at random and
# produced "Vertex Gaming / fuel", which undermines a demo people are meant to
# read as plausible.
MERCHANTS = [("Northwind Grocery", "grocery"), ("Blue Harbor Fuel", "fuel"),
             ("Cedar Pharmacy", "pharmacy"), ("Lumen Electronics", "retail"),
             ("Orchard Cafe", "food"), ("Pinnacle Sports", "retail"),
             ("Riverside Hardware", "retail"), ("Summit Travel", "travel"),
             ("Vertex Gaming", "gaming"), ("Willow Bookstore", "retail")]


def q(s: str) -> str:
    """Single-quote and escape a string for Spanner DML."""
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def batched_insert(table: str, cols: list[str], rows: list[tuple], size: int = 400):
    """Spanner caps mutations per commit, so emit multi-row INSERTs in batches."""
    out = []
    for i in range(0, len(rows), size):
        chunk = rows[i:i + size]
        values = ",\n  ".join("(" + ", ".join(chunk_v) + ")" for chunk_v in chunk)
        out.append(f"INSERT INTO {table} ({', '.join(cols)}) VALUES\n  {values};")
    return out


def build(rng: random.Random, n_clients: int, n_tx: int, days: int, start: dt.datetime):
    clients, devices, merchants = [], [], []
    used_device, paid, paid_merchant = [], [], []

    names = set()
    while len(names) < n_clients:
        names.add(f"{rng.choice(FIRST)}.{rng.choice(LAST)}")
    # Sort for determinism, then shuffle with the seeded rng. Without the
    # shuffle the ring members — which are simply the first few clients — all
    # shared a first name, which made the data look obviously fabricated.
    names = sorted(names)
    rng.shuffle(names)

    for i, n in enumerate(names):
        clients.append({
            "id": f"C{i:05d}",
            "name": n.replace(".", " ").title(),
            "email": f"{n}@example.com",
            "opened": (start - dt.timedelta(days=rng.randint(30, 900))).date().isoformat(),
            "risk": rng.choice(["low"] * 8 + ["medium"] * 3 + ["high"]),
        })

    # One device per client, plus a few spares. An earlier version assigned
    # devices round-robin from a small pool, which made EVERY device shared by
    # six accounts — so the planted rings were indistinguishable from the
    # background and the demo's central query returned noise. Sharing a device
    # has to be rare for it to mean anything.
    n_devices = n_clients + 10
    for i in range(n_devices):
        devices.append({
            "id": f"D{i:04d}",
            "kind": rng.choice(["ios", "android", "web"]),
            "first_seen": (start - dt.timedelta(days=rng.randint(1, 700))).date().isoformat(),
        })

    for i, (name, cat) in enumerate(MERCHANTS):
        merchants.append({"id": f"M{i:03d}", "name": name, "category": cat})

    # Ordinary behaviour: one account, one device.
    for i, c in enumerate(clients):
        used_device.append((c["id"], devices[i]["id"],
                            (start - dt.timedelta(days=rng.randint(0, days))).date().isoformat()))

    def ts(day_jitter: int = 0) -> str:
        d = start + dt.timedelta(days=rng.randint(0, max(0, days - 1)) + day_jitter,
                                 seconds=rng.randint(0, 86399))
        return d.replace(microsecond=0).isoformat() + "Z"

    txid = [0]
    def transfer(src: str, dst: str, amount: float, day_jitter: int = 0):
        txid[0] += 1
        paid.append((f"T{txid[0]:06d}", src, dst, round(amount, 2), ts(day_jitter)))

    # --- background traffic ---------------------------------------------------
    for _ in range(n_tx):
        a, b = rng.sample(clients, 2)
        transfer(a["id"], b["id"], rng.uniform(5, 400))
    for _ in range(n_tx // 2):
        c = rng.choice(clients); m = rng.choice(merchants)
        txid[0] += 1
        paid_merchant.append((f"T{txid[0]:06d}", c["id"], m["id"],
                              round(rng.uniform(3, 250), 2), ts()))

    # --- RING-A: shared device, closed cycle ----------------------------------
    ring_a = clients[:4]
    dev_a = devices[n_clients]["id"]      # a spare, not anyone's own
    for c in ring_a:
        used_device.append((c["id"], dev_a, (start + dt.timedelta(days=1)).date().isoformat()))
    amount = 9200.0
    for i in range(len(ring_a)):
        src = ring_a[i]["id"]; dst = ring_a[(i + 1) % len(ring_a)]["id"]
        transfer(src, dst, amount, day_jitter=0)
        amount *= 0.97          # a small skim each hop, the rest goes round

    # --- RING-B: shared device, fan-out to a collector, then one merchant -----
    ring_b = clients[4:7]
    collector = clients[7]
    dev_b = devices[n_clients + 1]["id"]  # a spare
    for c in ring_b + [collector]:
        used_device.append((c["id"], dev_b, (start + dt.timedelta(days=2)).date().isoformat()))
    for c in ring_b:
        transfer(c["id"], collector["id"], rng.uniform(2600, 3100))
    txid[0] += 1
    paid_merchant.append((f"T{txid[0]:06d}", collector["id"], merchants[8]["id"], 8400.00, ts()))

    # --- the honest false positive: a family sharing a tablet, no transfers ---
    family = clients[8:11]
    dev_f = devices[n_clients + 2]["id"]  # a spare
    for c in family:
        used_device.append((c["id"], dev_f, (start - dt.timedelta(days=200)).date().isoformat()))

    return clients, devices, merchants, used_device, paid, paid_merchant


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="generated")
    ap.add_argument("--clients", type=int, default=300)
    ap.add_argument("--transactions", type=int, default=2000)
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--seed", type=int, default=20260813)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    # Fixed start date, not "today" — a demo whose data changes per run cannot
    # have a last_verified date that means anything.
    start = dt.datetime(2026, 7, 1)

    clients, devices, merchants, used_device, paid, paid_merchant = build(
        rng, args.clients, args.transactions, args.days, start)

    stmts: list[str] = []
    stmts += batched_insert("Client", ["id", "name", "email", "opened_date", "risk_tier"],
                            [(q(c["id"]), q(c["name"]), q(c["email"]),
                              f"DATE {q(c['opened'])}", q(c["risk"])) for c in clients])
    stmts += batched_insert("Device", ["id", "kind", "first_seen"],
                            [(q(d["id"]), q(d["kind"]), f"DATE {q(d['first_seen'])}") for d in devices])
    stmts += batched_insert("Merchant", ["id", "name", "category"],
                            [(q(m["id"]), q(m["name"]), q(m["category"])) for m in merchants])
    stmts += batched_insert("UsedDevice", ["client_id", "device_id", "first_used"],
                            [(q(a), q(b), f"DATE {q(c)}") for a, b, c in used_device])
    stmts += batched_insert("Paid", ["tx_id", "src_client_id", "dst_client_id", "amount", "ts"],
                            [(q(t), q(s), q(d), str(a), f"TIMESTAMP {q(ti)}")
                             for t, s, d, a, ti in paid])
    stmts += batched_insert("PaidMerchant", ["tx_id", "client_id", "merchant_id", "amount", "ts"],
                            [(q(t), q(c), q(m), str(a), f"TIMESTAMP {q(ti)}")
                             for t, c, m, a, ti in paid_merchant])

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    p = out / "load.sql"
    p.write_text("\n\n".join(stmts) + "\n")

    print(f"  {p}")
    print(f"    {len(clients)} clients, {len(devices)} devices, {len(merchants)} merchants")
    print(f"    {len(used_device)} device links, {len(paid)} transfers, "
          f"{len(paid_merchant)} merchant payments")
    print(f"    {len(stmts)} batched INSERT statement(s)")
    print(FINDINGS)


if __name__ == "__main__":
    main()
