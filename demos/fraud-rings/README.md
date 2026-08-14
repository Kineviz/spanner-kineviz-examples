# Spanner Graph + Kineviz: fraud rings in P2P payments

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

## What you'll build

A property graph of synthetic peer-to-peer payments in Spanner — accounts, the devices they
sign in from, transfers between them, and merchant payments. Then you use it to find fraud
rings: accounts that share a device **and** move money between themselves.

The point is the pairing. A shared device on its own is a weak signal — families share
tablets, and this dataset contains one such family on purpose so you can watch a
device-only rule produce a false positive that the graph query correctly ignores.

<!-- TODO: hero screenshot of a ring on the Kineviz canvas -> img/hero.png -->

## At a glance

| | |
|---|---|
| **Backend** | Spanner Graph — **GA**, no preview terms |
| **Connection** | Kineviz Desktop → Spanner Property Graph ([how](../../connect/)) |
| **Dataset** | Synthetic, generated locally — nothing to download |
| **Time** | ~15 minutes, mostly loading rows |
| **Cost** | Storage only — see below, Spanner's model is not BigQuery's |
| **You need** | A Kineviz account (free for individual use, forever), and an **existing** Spanner instance |

> **Spanner bills for provisioned capacity continuously, not per query.** The instance is the
> expensive part and it costs money every hour it exists, queried or not. A database inside
> an instance you already run is storage-only — a few MB here.
>
> **So this demo creates a database, never an instance**, and teardown drops only that
> database. No instance yet? A
> [free trial instance](https://docs.cloud.google.com/spanner/docs/free-trial-instance) is 90
> days at no charge and is plenty for this.

## Architecture

```
        Kineviz Desktop
              │
              │  Spanner Property Graph
              ▼
   FraudGraph  (CREATE PROPERTY GRAPH)
              │
              ▼
   Client · Device · Merchant                ← nodes
   UsedDevice · Paid · PaidMerchant          ← edges
              │
              ▼
   a database in YOUR existing Spanner instance
              │
              │  seeded generator, no network
              ▼
   data/generate.py                          ← synthetic, reproducible
```

## Prerequisites

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Kineviz Desktop is **free
   for individual use, forever**, but the app requires sign-in. Do this first.
2. **Kineviz Desktop v0.17.1+** —
   [releases](https://github.com/Kineviz/kineviz-desktop/releases). ~600 MB installed,
   16 GB RAM.
3. **An existing Spanner instance**, and these roles on your account:
   - [`roles/spanner.databaseAdmin`](https://cloud.google.com/spanner/docs/iam#spanner.databaseAdmin) — create the demo database
   - [`roles/spanner.databaseReader`](https://cloud.google.com/spanner/docs/iam#spanner.databaseReader) — run GQL

   Kineviz itself only needs `databaseReader` + `spanner.viewer` to read the finished graph.
4. **`gcloud` and Python 3.9+** — [install the SDK](https://cloud.google.com/sdk/docs/install).

Preflight checks all of this and refuses to start if the instance is missing — it will not
create one for you, deliberately.

## Quick start

```bash
cp .env.example .env      # set GCP_PROJECT and SPANNER_INSTANCE
../../gxr up fraud-rings
```

## Or do it step by step

**1. Check prerequisites.** Creates nothing.

```bash
./scripts/preflight.sh
```

**2. Generate the payments.** Seeded, so the same numbers always produce the same graph —
including the rings the queries find.

```bash
set -a; . .env; set +a
python3 data/generate.py --out data/generated --seed "$FRAUD_SEED" \
  --clients "$FRAUD_CLIENTS" --transactions "$FRAUD_TRANSACTIONS" --days "$FRAUD_DAYS"
```

It prints the findings it planted, so you know what the queries should surface.

**3. Create the database and apply the schema.**

```bash
gcloud spanner databases create "$SPANNER_DATABASE" \
  --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT"

gcloud spanner databases ddl update "$SPANNER_DATABASE" \
  --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
  --ddl-file=sql/01_schema.ddl
```

[`sql/01_schema.ddl`](sql/01_schema.ddl) creates six tables and the `FraudGraph` property
graph over them.

**4. Load the rows.** The generator emits batched multi-row `INSERT`s because Spanner caps
mutations per commit.

```bash
# setup.sh does this in a loop; each statement is one batch
gcloud spanner databases execute-sql "$SPANNER_DATABASE" \
  --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
  --sql="$(head -1 data/generated/load.sql)"
```

**5. Verify.**

```bash
./scripts/verify.sh
```

This runs the demo's *headline* query, not a trivial smoke test. If no shared devices come
back, the graph works but the demo is pointless — so that counts as a failure.

## Connect Kineviz

The walkthrough is in **[`connect/`](../../connect/)** — the same flow for every demo here,
so it's documented once.

Values for this demo:

| Field | Value |
|---|---|
| Database Type | `Spanner Property Graph` |
| Upload Service Account | your service account JSON ([how to make one](../../connect/service-account.md)) |
| Select Instance | your `SPANNER_INSTANCE` |
| Select Database | `kineviz_fraud_demo` |
| Select Graph | `FraudGraph` |

## Explore

Four questions, in [`queries/`](queries/). **Run `01` then `02`** — that pair is the whole
argument for using a graph here.

**1. Which accounts share a device?** — [`01-shared-devices.gql`](queries/01-shared-devices.gql)

Three devices come back. One of them is innocent.

**2. Which of those also move money between themselves?** —
[`02-money-cycles.gql`](queries/02-money-cycles.gql)

Two devices survive. The family drops out — that's the false positive a shared-device list
would have handed an investigator. **Run this one in Kineviz**: a cycle is a shape.

**3. Which account is the fan-in point?** —
[`03-collector-accounts.gql`](queries/03-collector-accounts.gql)

The mule. Where 02 finds the ring, this finds the account worth freezing first.

**4. Where does the value leave?** — [`04-cash-out.gql`](queries/04-cash-out.gql)

Large merchant payments. Note the account here is the same one query 03 named — the
collector cashes out.

### What you should find

Seeded, so these are reproducible rather than lucky:

- **A ring of 4 accounts** sharing one device, moving ~$9,200 in a closed cycle and skimming
  a little at each hop. No account looks unusual alone.
- **A ring of 3 accounts** sharing a device and fanning money into a **fourth collector
  account**, which then makes one large gaming-merchant payment.
- **A family of 3 accounts** sharing a tablet with **no transfers between them** — present on
  purpose, and the reason to use a graph rather than a shared-device rule.

## How the graph is modeled

| Node label | Table | Key | Properties |
|---|---|---|---|
| `Client` | `Client` | `id` | `name`, `email`, `opened_date`, `risk_tier` |
| `Device` | `Device` | `id` | `kind`, `first_seen` |
| `Merchant` | `Merchant` | `id` | `name`, `category` |

| Edge label | From → To | Table | Properties |
|---|---|---|---|
| `USED_DEVICE` | `Client` → `Device` | `UsedDevice` | `first_used` |
| `PAID` | `Client` → `Client` | `Paid` | `tx_id`, `amount`, `ts` |
| `PAID_MERCHANT` | `Client` → `Merchant` | `PaidMerchant` | `tx_id`, `amount`, `ts` |

**Edge labels are declared explicitly and differ from the table names** — `UsedDevice` the
table, `USED_DEVICE` the label. GQL wants the label. That mismatch is the most common Spanner
Graph error, so `connect/verify.sh` prints the real labels for any graph.

### Pointing this at real data

Replace the six tables with your own and adjust the `CREATE PROPERTY GRAPH` at the bottom of
`sql/01_schema.ddl`. The queries only reference labels and properties, so they carry over as
long as the shape does: accounts, a shared-identity signal, and transfers.

## Troubleshooting

**Preflight: instance not found**

Deliberate — this demo will not create a Spanner instance, because an instance bills
continuously. List yours with `gcloud spanner instances list`, or start a
[free trial instance](https://docs.cloud.google.com/spanner/docs/free-trial-instance).

**`Failed to find element label [X]`**

Edge labels are not table names. Run [`connect/verify.sh`](../../connect/verify.sh), which
lists the real ones.

**`Syntax error: Unexpected keyword AT`**

`AT` is reserved in Spanner GQL. Don't alias a column `AS at` — these queries use
`occurred_at`.

**Loading is slow**

Expected. Rows go in via batched DML, and a free trial instance is deliberately small. It's
about a minute at the default size.

**`verify.sh` finds no shared devices**

Shouldn't happen — the data is seeded. If it does, `data/generate.py` and the demo have
drifted apart. That's a bug; please open an issue.

## Clean up

```bash
../../gxr down fraud-rings
```

Or by hand:

```bash
gcloud spanner databases delete "$SPANNER_DATABASE" \
  --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT"
```

**Teardown drops the database and never the instance.** An instance can hold databases
belonging to other people or other work, and it's also the thing that costs money — so
whether to keep it is your decision, not a script's.

## What's next

- [`connect/`](../../connect/) — point Kineviz at your own Spanner graph
- [Spanner Graph docs](https://docs.cloud.google.com/spanner/docs/graph/overview)
- [`bigquery-kineviz-examples`](https://github.com/Kineviz/bigquery-kineviz-examples) — the
  same patterns on BigQuery Graph
