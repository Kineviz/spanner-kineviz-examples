# Connect Kineviz to your own Spanner Graph

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.
> The screenshots below predate the rename; the steps are unchanged.

**You already have a Spanner property graph and want to see it in Kineviz.** That's this
page. About ten minutes, most of it the Desktop download, and it needs no demo data.

Want a worked example instead? See [`../demos/`](../demos/).

---

## Before you start

**1. A Kineviz account** — [sign up](https://www.kineviz.com/).

Kineviz Desktop is **free for individual use, forever** — no trial clock, no expiry. The app
does require sign-in, so create the account before downloading anything. For team or
commercial use, see [Kineviz licensing](https://www.kineviz.com/).

**2. A Spanner property graph.** Created with
[`CREATE PROPERTY GRAPH`](https://docs.cloud.google.com/spanner/docs/graph/set-up), in a
database you can read.

> **Spanner Graph is GA**, unlike BigQuery Graph. No preview terms, no reservation or edition
> requirement for GQL — if you can read the database, you can query the graph.

**3. Access.** A Google Cloud account with, at minimum:

| Role | Why |
|---|---|
| [`roles/spanner.databaseReader`](https://cloud.google.com/spanner/docs/iam#spanner.databaseReader) | Read the database and run GQL |
| [`roles/spanner.viewer`](https://cloud.google.com/spanner/docs/iam#spanner.viewer) | List instances and databases so Kineviz can offer them |

Read-only, and enough for production use. You only need write roles if you're *creating*
graphs.

**4. Room for Desktop** — about 200 MB to download, ~600 MB installed, plus 16 GB RAM.

---

## Know what Spanner costs before you connect

This is the one thing that differs sharply from BigQuery, and it catches people out.

**BigQuery bills per byte scanned — idle costs nothing. Spanner bills for provisioned
capacity, continuously, whether you query it or not.** An instance left running costs money
every hour it exists.

| | Cost |
|---|---|
| **Instance** | The expensive part. Charged per node / processing unit, per hour, forever |
| **Database** inside an existing instance | Storage only — effectively free at demo scale |
| **Queries** | No per-query charge |

Two consequences worth internalising:

- **Adding a database to an instance you already run is nearly free.** Every demo in this
  repo does that rather than creating an instance.
- **A [free trial instance](https://docs.cloud.google.com/spanner/docs/free-trial-instance)**
  is the right on-ramp if you have none: 90 days, no charge, enough for everything here.

Check what you already have:

```bash
gcloud spanner instances list --project="$GCP_PROJECT"
```

---

## 1 · Create a service account key

Kineviz Desktop authenticates to Spanner with a service account key file.

> **Treat the key like a password.** Anyone holding it has whatever access you granted.
> Scope it to the two read-only roles above, keep it out of version control (this repo's
> `.gitignore` and CI both block key files), and delete it when you're done.

**Console**

1. [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
   → **Create service account**.
2. Name it something you'll recognise later — `kineviz-reader`.
3. Grant it **Cloud Spanner Database Reader** and **Cloud Spanner Viewer**.
4. Open the account → **Keys** → **Add key** → **Create new key** → **JSON**. It downloads.

**gcloud**

```bash
PROJECT_ID=your-project-id

gcloud iam service-accounts create kineviz-reader \
  --project="$PROJECT_ID" \
  --display-name="Kineviz read-only"

for role in roles/spanner.databaseReader roles/spanner.viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:kineviz-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="$role" --condition=None --quiet
done

mkdir -p .gcp && chmod 700 .gcp
gcloud iam service-accounts keys create .gcp/key.json \
  --project="$PROJECT_ID" \
  --iam-account="kineviz-reader@${PROJECT_ID}.iam.gserviceaccount.com"
```

More detail, including rotation and how to avoid keys entirely on a GCE VM:
[`service-account.md`](service-account.md).

---

## 2 · Install Kineviz Desktop

Download the build for your machine from
[**Releases**](https://github.com/Kineviz/kineviz-desktop/releases) — v0.17.1 or later.

| Platform | File |
|---|---|
| macOS, Apple Silicon | `Kineviz-Desktop-<ver>-mac-arm64.dmg` |
| macOS, Intel | `Kineviz-Desktop-<ver>-mac-x64.dmg` |
| Windows x64 | `Kineviz-Desktop-Setup-<ver>-win-x64.exe` |
| Windows ARM64 | `Kineviz-Desktop-Setup-<ver>-win-arm64.exe` |
| Linux | `Kineviz-Desktop-<ver>-linux-x86_64.AppImage` or the `.deb` |

Not sure which Mac you have: menu → **About This Mac** → **Chip**.

Install, launch, and sign in with the account from *Before you start*.

**Two alternatives, same connection flow:**

- **[The hosted portal](https://graphxr.kineviz.com/)** — nothing to install.
- **[`graphxr-database-proxy`](https://github.com/Kineviz/graphxr-database-proxy)** — a
  zero-trust middleware that keeps the service account key on a server you control rather
  than in the desktop app. It ships a Spanner driver, and it is the right answer when a
  credential must not sit on an analyst's laptop. See [below](#alternative-via-the-database-proxy).

---

## 3 · Connect

Two dialogs in Kineviz Desktop: create the project, then the connection wizard.

### Create the project

**1. Click Create New Project**

<!-- TODO: screenshot of Create New Project -> img/01_create_project.png -->

**2. Enter a Project Name, and set Database Type to `Spanner Property Graph`** — then
**Confirm**

<!-- TODO: screenshot of name + database type -> img/02_select_name_type.png -->

### Connect to Spanner

**3. Upload Service Account** — the `key.json` from step 1

**4. Select Instance** — the Spanner instance holding your database

**5. Select Database**

**6. Select Graph** — the name from your `CREATE PROPERTY GRAPH` — then **Connect**

The canvas opens. Hit **Search**, pick a node label, and run it to pull your first nodes.

### Alternative: via the database proxy

If the key must not live on the laptop, run
[`graphxr-database-proxy`](https://github.com/Kineviz/graphxr-database-proxy), create a
Spanner project in its web UI, copy the API URL it gives you, and in Kineviz choose database
type **Database Proxy** and paste that URL. The proxy holds the credential; Kineviz never
sees it.

---

## Verify

To check the graph is reachable *before* opening Kineviz — useful when something isn't
working and you want to know which side is at fault:

```bash
./verify.sh --project my-project --instance my-instance --database my-db --graph MyGraph
```

It lists the graph's labels and runs a real GQL query. If this passes and Kineviz still
can't see the graph, the problem is the connection settings, not Spanner.

---

## Troubleshooting

**`Failed to find element label [X]`**

The most common Spanner Graph mistake, and an easy one: **edge labels are often not the same
as table names.** A table `Client_Perform_Transaction` may declare `LABEL PERFORMS`, and GQL
wants the label. List the real ones:

```bash
gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" \
  --sql="SELECT PROPERTY_GRAPH_METADATA_JSON FROM information_schema.property_graphs
         WHERE property_graph_name='$GRAPH'"
```

`verify.sh` prints them for you.

**No instances listed after uploading the key**

Usually a missing `roles/spanner.viewer` — reading a database and *listing* what exists are
separate permissions.

**"Permission denied" with a valid key**

The service account needs its roles on the project that owns the *instance*, which isn't
always the project the key was created in.

**Queries are slower than expected**

Spanner performance tracks provisioned capacity. A free trial instance is deliberately small;
that's fine for demos and not representative of a production instance.

**Desktop won't sign in**

An account is required, and it's free for individual use.
[Sign up](https://www.kineviz.com/), then sign in.

**Still stuck?** [Open an issue](https://github.com/Kineviz/spanner-kineviz-examples/issues/new?template=demo-bug.yml)
with the error and your Desktop version. Redact project IDs; never paste a key.

---

## What's next

- [`../demos/`](../demos/) — worked examples that build a graph for you
- [Spanner Graph docs](https://docs.cloud.google.com/spanner/docs/graph/overview)
- [`bigquery-kineviz-examples`](https://github.com/Kineviz/bigquery-kineviz-examples) ·
  [`alloydb-kineviz-examples`](https://github.com/Kineviz/alloydb-kineviz-examples)
