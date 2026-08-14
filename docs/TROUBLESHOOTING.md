# Troubleshooting

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

Problems that span demos. Demo-specific issues are in each demo's README.

## Start here

```bash
./gxr doctor
./connect/verify.sh --project P --instance I --database D --graph G
```

`connect/verify.sh` tells you which side is at fault, and prints the graph's real labels.

## Spanner Graph

**`Failed to find element label [X]`**

The most common Spanner Graph error by some margin. **Edge labels are frequently not the
table names** — a table `UsedDevice` may declare `LABEL USED_DEVICE`, and GQL wants the
label. `connect/verify.sh` lists them.

**`Syntax error: Unexpected keyword AT`**

`AT` is reserved. Don't alias a column `AS at`.

**`Returning expressions of type GRAPH_PATH is not allowed`**

Spanner GQL, like BigQuery's, will not let you `RETURN` a path variable. Return the endpoints
and a hop count instead.

**`Syntax error` on `HAVING`**

GQL has no `HAVING`. Aggregate, then chain: `... GROUP BY x NEXT FILTER agg > n RETURN ...`.

**"The name X is already defined" in a subquery**

You cannot rebind a graph variable inside a subquery. Bind a fresh name and tie it back with
an explicit id filter.

## Instances and cost

**Preflight says the instance doesn't exist**

Deliberate. Demos here add a database to an instance you already run; they do not create one,
because an instance bills continuously. See [COSTS.md](COSTS.md).

**Queries feel slow**

Spanner performance tracks provisioned capacity. A free trial instance is small by design —
fine for demos, not representative of production.

## Connecting

**No instances listed after uploading the key**

Usually a missing `roles/spanner.viewer`. Reading a database and *listing* what exists are
separate permissions.

**"Permission denied" with a valid key**

The service account needs its roles on the project that owns the **instance**, which isn't
always where the key was made.

**Desktop won't sign in**

An account is required, free for individual use. [Sign up](https://www.kineviz.com/).

## Getting help

[Open an issue](https://github.com/Kineviz/spanner-kineviz-examples/issues/new?template=demo-bug.yml)
with the demo, the step, the full error including its `REMEDIATION:` line, and your versions.

**Redact project IDs, and never paste a service account key.**
