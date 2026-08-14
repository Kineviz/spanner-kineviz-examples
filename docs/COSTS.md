# What this repo costs

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

**Kineviz Desktop is free for individual use, forever.** The Google Cloud side is where the
money is, and Spanner's model is the opposite of BigQuery's.

## The one thing to understand

| | Billing | Idle cost |
|---|---|---|
| **BigQuery** | per byte scanned | nothing |
| **Spanner** | provisioned capacity, per hour | **the full rate** |

A Spanner instance costs money every hour it exists, whether or not anyone queries it. The
data is almost free; the capacity is not.

## What the demos actually create

| Demo | Creates | Cost |
|---|---|---|
| `fraud-rings` | one **database** in an instance you already run | storage only — a few MB |

**No demo here creates an instance.** Preflight fails if the one you named does not exist,
and tells you why rather than quietly provisioning something billable.

## If you have no instance

A [free trial instance](https://docs.cloud.google.com/spanner/docs/free-trial-instance) is
90 days at no charge and is enough for everything in this repo.

```bash
gcloud spanner instances list --project="$GCP_PROJECT"
```

## Teardown

```bash
./gxr down <demo>
```

Drops the demo's database. **It never touches the instance** — an instance can hold other
people's databases, and it is also the recurring charge, so keeping or deleting it is your
call. If you created one purely for this repo, delete it yourself when you're done:

```bash
gcloud spanner instances delete "$SPANNER_INSTANCE" --project="$GCP_PROJECT"
```

## If something surprised you

Open an issue. An unexpected charge from an example repo is a bug in the example.
