# Service account keys for Kineviz + Spanner

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

Detail behind step 1 of [the connect guide](README.md) — least privilege, rotation, and how
to avoid keys entirely.

## Least privilege

Kineviz reads. It does not need to write, and it should not be able to.

| Role | Grants | Needed for |
|---|---|---|
| [`roles/spanner.databaseReader`](https://cloud.google.com/spanner/docs/iam#spanner.databaseReader) | Read a database and run GQL | Reading the graph |
| [`roles/spanner.viewer`](https://cloud.google.com/spanner/docs/iam#spanner.viewer) | List instances and databases | So Kineviz can offer them in the dialog |

Those two are the whole set for production use.

**Do not grant `roles/spanner.admin` or `roles/editor`.** They're broad, they're what a
security reviewer flags first, and nothing here needs them.

If you're also *creating* graphs — running the demos in this repo, say — add
`roles/spanner.databaseAdmin` **for that work only**, and use a separate account from the one
Kineviz connects with.

### Scope to a dataset instead of the project

Tighter than a project-level grant, and worth it if the project holds anything Kineviz
shouldn't see:

```bash
PROJECT_ID=your-project-id
DATASET=your_dataset
SA="kineviz-reader@${PROJECT_ID}.iam.gserviceaccount.com"

# dataViewer on the one dataset
bq show --format=prettyjson "$PROJECT_ID:$DATASET" > /tmp/ds.json
python3 - <<PY
import json
d = json.load(open("/tmp/ds.json"))
d.setdefault("access", []).append({"role": "READER", "userByEmail": "$SA"})
json.dump(d, open("/tmp/ds.json", "w"))
PY
bq update --source /tmp/ds.json "$PROJECT_ID:$DATASET"

# jobUser still has to be project-level — running a job is a project operation
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA" --role="roles/bigquery.jobUser" \
  --condition=None --quiet
```

## Handling the key file

A service account key is a long-lived credential. Anyone with the file has everything you
granted it.

- **Keep it out of the repo.** `.gitignore` covers `.gcp/`, `*key.json`, and
  `*credentials*.json`, and `.github/workflows/secrets.yml` fails the build on both key
  contents and key filenames. Don't work around either.
- **Restrict it locally.**
  ```bash
  mkdir -p .gcp && chmod 700 .gcp
  chmod 600 .gcp/key.json
  ```
- **Never paste it anywhere** — issues, chat, screenshots. If you need help, share the
  service account *email*, never the file.
- **Never give it to an agent.** Agents in this repo are instructed not to handle
  credentials or sign-ins ([`AGENTS.md`](../AGENTS.md)); don't route around that.
- **Delete it when you're done.**

## Rotation

Keys don't expire on their own. Rotate on a schedule and after any suspected exposure.

```bash
SA="kineviz-reader@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts keys list --iam-account="$SA"

# create the new one and re-upload it in Kineviz before deleting the old
gcloud iam service-accounts keys create .gcp/key-new.json --iam-account="$SA"
gcloud iam service-accounts keys delete <OLD_KEY_ID> --iam-account="$SA"
```

If a key leaks, delete it first and investigate second — a deleted key stops working
immediately.

## Better: no key at all

Keys exist because a laptop has no ambient Google identity. Where that isn't true, skip them.

**On a GCE VM or Cloud Shell**, attach the service account to the instance and use
[Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials).
Nothing to store, nothing to rotate, nothing to leak:

```bash
gcloud auth application-default login   # local dev
```

The `bq` commands in this repo — including [`verify.sh`](verify.sh) — use ADC and need no key
file. Only Kineviz Desktop's connection dialog requires one.

**In your own GCP project**, the
[GraphXR Explorer for BigQuery](https://console.cloud.google.com/marketplace/product/kineviz-public/graphxr-explorer-for-bigquery)
Marketplace deployment runs inside your environment and uses your project's identity, so no
key leaves it. That's the right answer for regulated environments.

## Verifying what a key can do

Before handing it to Kineviz, confirm it has what it needs and nothing more:

```bash
gcloud auth activate-service-account --key-file=.gcp/key.json
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:kineviz-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

# should succeed
bq --project_id="$PROJECT_ID" ls "$DATASET"

# should FAIL — if it succeeds, the account is over-privileged
bq --project_id="$PROJECT_ID" mk --table "${PROJECT_ID}:${DATASET}.should_not_exist" x:STRING
```

Then switch back to your own identity:

```bash
gcloud config set account you@example.com
```
