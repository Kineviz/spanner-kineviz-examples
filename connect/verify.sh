#!/usr/bin/env bash
#
# Prove a Spanner property graph is reachable and queryable — before involving
# Kineviz at all. If this passes and Kineviz still cannot see your graph, the
# problem is the connection settings, not Spanner.
#
#   ./verify.sh --project P --instance I --database D --graph G
#
# Creates nothing. Reads only.

set -euo pipefail

PROJECT=""; INSTANCE=""; DATABASE=""; GRAPH=""; JSON=0

usage() {
  cat <<'EOF'
Usage: ./verify.sh --project <id> --instance <name> --database <name> --graph <name> [--json]

  --project    Google Cloud project that owns the Spanner instance
  --instance   Spanner instance id
  --database   Spanner database id
  --graph      Property graph name (from CREATE PROPERTY GRAPH)
  --json       Machine-readable output
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT="${2:-}"; shift 2 ;;
    --instance) INSTANCE="${2:-}"; shift 2 ;;
    --database) DATABASE="${2:-}"; shift 2 ;;
    --graph)    GRAPH="${2:-}"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  usage 0 ;;
    *)          echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

_c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_green=$'\033[32m'; _c_dim=$'\033[2m'
[ -t 1 ] || { _c_reset=""; _c_red=""; _c_green=""; _c_dim=""; }

die() {
  if [ "$JSON" = 1 ]; then
    printf '{"ok":false,"error":"%s","remediation":"%s"}\n' "$1" "$2" >&2
  else
    printf '\n  %s✗%s %s\n    REMEDIATION: %s\n\n' "$_c_red" "$_c_reset" "$1" "$2" >&2
  fi
  exit 1
}
ok()   { [ "$JSON" = 1 ] || printf '  %s✓%s %s\n' "$_c_green" "$_c_reset" "$1"; }
note() { [ "$JSON" = 1 ] || printf '    %s%s%s\n' "$_c_dim" "$1" "$_c_reset"; }

[ -n "$PROJECT" ] && [ -n "$INSTANCE" ] && [ -n "$DATABASE" ] && [ -n "$GRAPH" ] || \
  die "Missing required arguments." "Run ./verify.sh --help"

command -v gcloud >/dev/null 2>&1 || \
  die "'gcloud' not found on PATH." "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"

sql() { gcloud spanner databases execute-sql "$DATABASE" \
          --instance="$INSTANCE" --project="$PROJECT" --sql="$1" 2>&1; }

[ "$JSON" = 1 ] || printf '\nChecking %s / %s / %s → graph %s\n\n' \
  "$PROJECT" "$INSTANCE" "$DATABASE" "$GRAPH"

# 1 — the database is reachable at all.
out=$(gcloud spanner databases describe "$DATABASE" --instance="$INSTANCE" \
        --project="$PROJECT" --format='value(state)' 2>&1) || \
  die "Cannot reach database '$DATABASE' in instance '$INSTANCE'." \
      "Check the names, and that your account has roles/spanner.databaseReader on the project that OWNS the instance."
ok "database reachable (state: $out)"

# 2 — the property graph is registered.
graphs=$(sql "SELECT property_graph_name FROM information_schema.property_graphs" | tail -n +2)
printf '%s\n' "$graphs" | grep -qx "$GRAPH" || \
  die "No property graph named '$GRAPH' in $DATABASE." \
      "Graphs present: $(printf '%s' "$graphs" | tr '\n' ' ' | sed 's/  */ /g'). Names are case-sensitive."
ok "property graph '$GRAPH' is registered"

# 3 — surface the LABELS, not the table names.
#
# This is the single most common Spanner Graph mistake: a table called
# Client_Perform_Transaction may declare LABEL PERFORMS, and GQL wants the
# label. Getting this wrong produces "Failed to find element label [X]", which
# reads like the graph is broken when only the query is.
meta=$(sql "SELECT PROPERTY_GRAPH_METADATA_JSON FROM information_schema.property_graphs
            WHERE property_graph_name='$GRAPH'" | tail -n +2)
labels=$(printf '%s' "$meta" | python3 -c "
import json,sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
n = sorted({l for t in d.get('nodeTables', []) for l in t.get('labelNames', [])})
e = sorted({l for t in d.get('edgeTables', []) for l in t.get('labelNames', [])})
print('NODE:' + ','.join(n))
print('EDGE:' + ','.join(e))
" 2>/dev/null)
node_labels=$(printf '%s\n' "$labels" | sed -n 's/^NODE://p')
edge_labels=$(printf '%s\n' "$labels" | sed -n 's/^EDGE://p')
if [ -n "$node_labels" ]; then
  ok "labels resolved"
  note "node labels: ${node_labels}"
  note "edge labels: ${edge_labels}"
  note "use these in GQL — they are often NOT the table names"
fi

# 4 — it actually answers a GQL query. Steps 1-3 only prove registration.
first_node=$(printf '%s' "$node_labels" | cut -d, -f1)
[ -n "$first_node" ] || first_node=""
q="GRAPH $GRAPH MATCH (n) RETURN COUNT(n) AS node_count"
out=$(sql "$q") || true
if printf '%s' "$out" | grep -qiE 'ERROR|INVALID_ARGUMENT'; then
  err=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
  case "$err" in
    *"Failed to find element label"*)
      die "GQL ran but a label was not found: $err" \
          "Use the labels listed above, not the table names." ;;
    *"PERMISSION_DENIED"*)
      die "Permission denied running GQL." \
          "The account needs roles/spanner.databaseReader on the project that owns the instance." ;;
    *)
      die "GQL query failed: $err" "Confirm the graph's node tables are readable, then re-run." ;;
  esac
fi
nodes=$(printf '%s\n' "$out" | tail -1 | tr -d ' \r')
ok "GQL query succeeded (graph has ${nodes:-?} nodes)"

if [ "$JSON" = 1 ]; then
  printf '{"ok":true,"project":"%s","instance":"%s","database":"%s","graph":"%s","nodes":%s,"node_labels":"%s","edge_labels":"%s"}\n' \
    "$PROJECT" "$INSTANCE" "$DATABASE" "$GRAPH" "${nodes:-0}" "$node_labels" "$edge_labels"
else
  cat <<EOF

  ${_c_green}Ready to connect.${_c_reset} In Kineviz Desktop → Create New Project:

    Database Type          : Spanner Property Graph
    Upload Service Account : your service account JSON
    Select Instance        : $INSTANCE
    Select Database        : $DATABASE
    Select Graph           : $GRAPH

  Walkthrough with screenshots: connect/README.md § 3 · Connect

EOF
fi
