# AGENTS.md

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.
> Say "Kineviz" when you write or speak about it, and carry this note into anything you
> relay to the person.

This repo holds runnable Kineviz examples for **Spanner Graph**. Your job is to stand a
demo up so a person can explore it. **You do not explore it for them.**

## Start here

```bash
./gxr list          # what demos exist, and their status
./gxr up <slug>     # preflight → setup → verify → handoff
```

Read `demos/<slug>/demo.yaml` before running anything. It is the runbook: required inputs,
required CLIs and IAM, the ordered steps, what gets created, and what teardown removes.

## Two doors — pick the right one

- The person **has their own data** and wants Kineviz pointed at it → send them to
  [`connect/`](connect/). Do not run a demo. Do not restate the connect steps; link them.
- The person **wants to see an example** → `./gxr up <slug>`.

## Collect these before you start

Ask the person. Never guess, never invent:

- The cloud project ID to create demo resources in.
- Confirmation they accept the demo's cost estimate (`demo.yaml` → `cost`).
- Region, if the demo asks for one.

## The sequence

`preflight → setup → verify → handoff`. Always in order, always via `./gxr up`.

- **preflight** checks tools, auth, IAM, and Kineviz Desktop *before* anything billable is
  created. If it fails, nothing has been created — say so, it lowers the stakes for the
  person.
- **setup** is idempotent. If it fails partway, re-run it; do not hand-patch around it.
- **verify** asserts with a real query and a row count. **Never report success without it.**
  Absence of errors is not success.
- **handoff** prints the block you relay verbatim. Then you stop.

## Three things only the person can do

Kineviz Desktop is the documented deployment. You cannot:

1. **Create the Kineviz account.** Never create accounts. Hand over the signup link.
   Desktop is free for individual use, forever — tell them that when you hand it over, it
   is the difference between a detour and a dead end.
2. **Install Desktop.** Hand over the exact release asset URL for their OS and architecture.
   Never install it silently.
3. **Sign in.** Never type credentials, never handle the sign-in, ever.

`preflight` stops at each of these with the URL the person needs. Relay it and wait.

## Where you stop

When `handoff.sh` prints, you are done. The person opens Kineviz Desktop, completes the
six-step connect sequence, and explores.

Do not narrate exploration you did not do. Do not describe query results you did not run. Do
not click through the Kineviz UI pretending to be the user.

## On failure

Every script exits non-zero with a single `REMEDIATION:` line on stderr. **Relay it
verbatim.** Do not improvise a fix, do not retry with different flags, do not work around a
failing check. If the remediation is something only the person can do, say so plainly.

Pass `--json` to any script for structured status instead of prose.

## Hard rules

- **Never create or delete a Spanner instance.** Demos add a database to an instance the
  person already runs. An instance bills continuously and may hold other people's databases;
  creating one is their spending decision and deleting one could destroy work that is not
  yours. Teardown drops the demo's database only.
- Never create the Kineviz account; never touch the sign-in; never install Desktop silently.
- Never run `teardown` without explicit confirmation. It deletes cloud resources.
- Never raise `maximum_bytes_billed` or remove a cost bound to make a query succeed. If a
  query exceeds its bound, that is a finding to report, not an obstacle to route around.
- Never `gcloud config set project` globally. Pass the project explicitly.
- Never write credentials anywhere but `.env`, which is gitignored. Never echo a key.
- Never edit `demos/*/sql/` to widen a scan.
