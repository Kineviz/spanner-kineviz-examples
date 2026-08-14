# Security

## Reporting a vulnerability

Email **security@kineviz.com**. Please do not open a public issue for a security report.

## What this repo is

Example code and documentation. It creates cloud resources in **your** project using **your**
credentials. It contains no secrets, and it never should.

## If you find a credential in this repo

Report it as above and treat it as live: assume it is compromised and needs rotating, even
if it looks like a placeholder.

## Handling credentials in these demos

- **Never commit a credential.** `.env.example` holds placeholders; `.env` is gitignored.
  CI blocks both secret contents (gitleaks) and credential filenames.
- **Service account keys stay out of the repo tree.** The demos write to `./.gcp/`, which is
  gitignored. Prefer Application Default Credentials where the backend supports it.
- **Least privilege.** Every demo lists the exact roles it needs in `demo.yaml` under
  `requires.iam`, and each `connect/` guide states the smaller read-only set sufficient for
  production use.
- **Agents never handle credentials.** See `AGENTS.md`: an agent does not create the Kineviz
  account, does not sign in, and does not echo a key.

## Cost as a safety property

A runaway query is a real harm in a public example repo. Every billable demo bounds its
queries, materializes a small table instead of rescanning a public dataset, and ships a
teardown that deletes what it created. Never widen a bound to make a query pass.
