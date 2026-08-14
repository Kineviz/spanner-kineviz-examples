#!/usr/bin/env bash
# Prove the graph works AND that the planted rings are findable.
# Asserts, does not describe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=verify
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Verify — running the shared-device ring query"

load_env "$DEMO_DIR"
require_env GCP_PROJECT SPANNER_INSTANCE SPANNER_DATABASE SPANNER_GRAPH

# Deliberately the demo's headline query, not a trivial smoke test: if this
# returns nothing the graph "works" but the demo is pointless.
out=$(gcloud spanner databases execute-sql "$SPANNER_DATABASE" \
        --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
        --sql="GRAPH $SPANNER_GRAPH
               MATCH (c:Client)-[:USED_DEVICE]->(d:Device)
               RETURN d.id AS device, COUNT(DISTINCT c.id) AS accounts
               GROUP BY device
               NEXT
               FILTER accounts > 1
               RETURN device, accounts
               ORDER BY accounts DESC" 2>&1) || true

if printf '%s' "$out" | grep -qiE 'ERROR|INVALID_ARGUMENT'; then
  e=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
  case "$e" in
    *"Failed to find element label"*)
      die "GQL ran but a label was not found: $e" \
          "Edge labels are not table names in Spanner. Run ../../connect/verify.sh to list the real ones." ;;
    *PERMISSION_DENIED*)
      die "Permission denied running GQL." \
          "You need roles/spanner.databaseReader on $GCP_PROJECT." ;;
    *)
      die "Verification query failed: $e" \
          "Re-run './gxr up fraud-rings' — setup is idempotent." ;;
  esac
fi

rows=$(printf '%s\n' "$out" | tail -n +2 | grep -c . || true)
[ "${rows:-0}" -ge 1 ] || die "No shared devices found — the demo's central finding is missing." \
  "The data is seeded, so this should not happen. Re-run setup; if it persists, open an issue."

ok "found $rows device(s) shared by more than one account"
[ "$GXR_JSON" = 1 ] || printf '%s\n' "$out" | sed 's/^/      /'
echo "$rows" > "$DEMO_DIR/.verified_rows"
