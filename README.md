# Spanner Graph + Kineviz

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

Explore [Spanner property graphs](https://docs.cloud.google.com/spanner/docs/graph/overview)
visually in Kineviz. Two ways in — pick the one that matches why you're here.

---

### 🔌 I have my own Spanner graph

**→ [`connect/`](connect/)** — point Kineviz at an existing property graph. About ten
minutes, no demo data.

### 📊 Show me what this looks like

**→ [`demos/`](demos/)** — a worked example that builds a graph in your own instance,
verifies it, and hands you questions to ask.

---

## Demos

<!-- BEGIN GENERATED DEMOS -->

| Demo | What it shows | Level | Time | Cost |
|---|---|---|---|---|
| [`fraud-rings`](demos/fraud-rings/) | Build a property graph of synthetic P2P payments in Spanner and find the accounts that share a device and move money between themselves. | beginner | 15 min | free |

<!-- END GENERATED DEMOS -->

Generated from each demo's `demo.yaml` — edit that, not this table.

## Quick start

```bash
git clone https://github.com/Kineviz/spanner-kineviz-examples
cd spanner-kineviz-examples
./gxr list
./gxr up fraud-rings
```

## What you need

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Kineviz Desktop is **free
   for individual use, forever**; the app requires sign-in, so do this first.
2. **[Kineviz Desktop](https://github.com/Kineviz/kineviz-desktop/releases)** v0.17.1+ —
   Windows, macOS, or Linux. ~600 MB installed, 16 GB RAM.
3. **An existing Spanner instance**, plus `gcloud` and Python 3.9+.

> **Spanner Graph is GA** — no preview terms, and no edition or reservation requirement for
> GQL. If you can read the database, you can query the graph.

## Cost — read this once

Spanner's model is the opposite of BigQuery's, and it is the thing that catches people out.

| | |
|---|---|
| **BigQuery** | per byte scanned. Idle costs nothing |
| **Spanner** | provisioned capacity, **billed continuously** whether you query or not |

So the expensive object is the **instance**, not the data. Every demo here creates a
**database** inside an instance you already run — storage only, a few MB — and teardown drops
only that database, never the instance, which may hold other people's work.

No instance? A [free trial instance](https://docs.cloud.google.com/spanner/docs/free-trial-instance)
is 90 days at no charge and covers everything in this repo.

```bash
./gxr down <demo>    # drops the demo's database; leaves your instance alone
```

## Using an agent

Point Claude Code, Codex, or Cursor at this repo — [`AGENTS.md`](AGENTS.md) tells it how to
stand a demo up. Three things it won't do, by design: create your Kineviz account, install
Desktop, or sign in for you.

## Repo layout

| Path | |
|---|---|
| [`connect/`](connect/) | Connect Kineviz to your own graph — standalone |
| [`demos/`](demos/) | Worked examples |
| [`AGENTS.md`](AGENTS.md) | Agent entry point |
| `gxr` | `list · preflight · up · verify · down · doctor` |
| `tools/` | `check_contract.py`, `selftest.sh`, `preview.sh`, `gen_index.py` |

## Related

- [`bigquery-kineviz-examples`](https://github.com/Kineviz/bigquery-kineviz-examples) — BigQuery Graph
- [`alloydb-kineviz-examples`](https://github.com/Kineviz/alloydb-kineviz-examples) — AlloyDB and PostgreSQL
- [`kineviz-desktop`](https://github.com/Kineviz/kineviz-desktop) — the app
- [`graphxr-database-proxy`](https://github.com/Kineviz/graphxr-database-proxy) — zero-trust
  middleware with a Spanner driver, if a credential must not sit on a laptop

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Demo suggestions welcome — the dataset must be public
or synthetic.

## License

[MIT](LICENSE)
