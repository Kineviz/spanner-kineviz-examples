# Contributing

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

Two audiences read this repo: a person following a README, and an agent following
[`AGENTS.md`](AGENTS.md). Everything below exists to keep both working.

## The rule that matters most

**The scripts are the single source of truth, and neither audience has a step the other
lacks.**

- `./gxr up <slug>` is the fast path for *people too*, not an agent shortcut.
- Every scripted step also appears in the demo README as the literal commands, in order,
  copy-pasteable. This serves the person who wants to understand it, the person in a
  restricted environment who cannot run an unreviewed script, and the reviewer who wants to
  see the API calls without reading bash. `docs-drift.yml` fails a PR where the two diverge.
- Nothing that matters lives only in a script. Decisions and gotchas go in the README prose
  **and** in `demo.yaml`.

## Adding a demo

```bash
cp -r demos/_template demos/my-demo
$EDITOR demos/my-demo/demo.yaml
./gxr doctor            # structural checks, same as CI
./tools/selftest.sh     # behavioural checks, no cloud needed
./tools/preview.sh      # see your README rendered before pushing
```

`contract.yml` will reject a PR that misses any of:

- The required files (`demo.yaml`, `README.md`, all five scripts, executable).
- A `demo.yaml` that validates against `schema/demo.schema.json`.
- The README headings, in order.
- The naming note (below).
- A link to `connect/` — and **no inlined copy** of the connect steps.
- A `teardown.sh` and a `creates:` list, if the demo creates anything billable.

## Script rules

Non-negotiable, most are CI-checked:

- **`set -euo pipefail`** at the top. Checked.
- **Executable.** Checked.
- **Idempotent.** Re-running `setup.sh` after a partial failure converges. Both people and
  agents retry.
- **Non-interactive.** No prompts; inputs come from env or flags. `gcloud --quiet`. The one
  exception is `teardown`, which always confirms.
- **One `REMEDIATION:` line on failure.** Use `die "what broke" "what to do"`. Agents relay
  it verbatim, so it must be actionable by the person, not by the agent.
- **`--json` supported.** `source shared/lib/common.sh` gives you this free.
- **`verify.sh` asserts, it does not describe.** Run a real query, check a row count. The
  absence of errors is not success, and reporting success you did not verify is the one
  unrecoverable failure in a demo repo.
- **`preflight.sh` creates nothing.** It runs before any billable resource exists, and it
  should say so when it fails — it lowers the stakes for the person reading.
- **`teardown.sh` deletes exactly what `setup.sh` created**, from the `creates:` list, and
  nothing else.
- **Readable.** Commented, no clever one-liners. A person should be able to read `setup.sh`
  and learn to do it by hand.

## Data

- **5 MB per demo, committed.** Above that, ship `data/generate.py` with a fixed seed, or
  read from a public dataset. No Git LFS — it makes forking worse, and forking is how these
  repos get used.
- **Synthetic or public data only.** Never customer data, never anything under NDA.

## Cost

Any demo that touches a billable service must:

- Bound every query (`maximum_bytes_billed` or the backend's equivalent).
- Materialize a small table rather than scanning a public dataset repeatedly.
- Declare `cost.estimate_usd`, `cost.bounded_by`, and `cost.billable_resources`.
- Ship a `teardown.sh` that actually deletes them.

Never widen a bound to make a query pass. If a query exceeds its bound, that is a finding.

## The naming note

GraphXR is a retired brand; the product is Kineviz. The rename is mid-flight — the
Marketplace listing, the portal hostname, and existing screenshots still show the old name —
so the note is what reconciles a UI saying GraphXR with docs saying Kineviz. Without it,
someone hitting that mismatch assumes the docs are stale.

Use this string verbatim, at the top of every README, `AGENTS.md`, `connect/README.md`, and
each `docs/*.md`:

```markdown
> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.
```

In prose, always write Kineviz. Leave proper nouns alone — the Marketplace listing name, the
portal hostname, existing repo names — because a reader will click them and must find what
the text promised.

## Kineviz Desktop version

Declare a **floor**, not an exact pin:

```yaml
requires:
  kineviz_desktop: ">=0.17.1"
```

A floor is friendlier to someone already running Desktop and avoids a demo refusing to start
because the person is *ahead*. `desktop-floor.yml` opens a PR when a new release ships;
`last_verified` and `verified_with` record what was actually tested.

## What never goes in these repos

- Customer data, of any kind.
- Credentials. `.env.example` only, never `.env`. `secrets.yml` blocks both the contents and
  the filenames.
- Gated artifacts — no image that needs a password from an engineer.
- Internal material: benchmark submissions, sales decks, roadmaps.
