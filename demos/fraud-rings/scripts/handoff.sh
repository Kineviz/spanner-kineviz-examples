#!/usr/bin/env bash
# Everything above was automatable. Everything below is the person's.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=handoff
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env "$DEMO_DIR"
rows=$(cat "$DEMO_DIR/.verified_rows" 2>/dev/null || echo "?")
desktop="not detected"; kineviz_desktop_installed && desktop="detected"

cat <<EOF

✅ Demo ready: fraud-rings
   Kineviz (formerly GraphXR)

   Instance:  ${SPANNER_INSTANCE}   (not created by this demo, and not deleted by teardown)
   Database:  ${SPANNER_DATABASE}   (synthetic, ${FRAUD_CLIENTS} accounts, seed ${FRAUD_SEED})
   Graph:     ${SPANNER_GRAPH} — Client, Device, Merchant / USED_DEVICE, PAID, PAID_MERCHANT
   Verified:  ${rows} shared device(s) found
   Desktop:   ${desktop}

   Last step — connect Kineviz (about 60 seconds):
     Open Kineviz Desktop → Create New Project
       → Database Type:          Spanner Property Graph
       → Upload Service Account: your service account JSON
       → Select Instance:        ${SPANNER_INSTANCE}
       → Select Database:        ${SPANNER_DATABASE}
       → Select Graph:           ${SPANNER_GRAPH}
     Walkthrough: ../../connect/README.md

   Then try:
     1. Accounts sharing a device            queries/01-shared-devices.gql
     2. Money moving in a closed cycle       queries/02-money-cycles.gql
     3. Fan-in to a collector account        queries/03-collector-accounts.gql
     4. Where value leaves the network       queries/04-cash-out.gql

     Run 2 in Kineviz rather than the CLI — a cycle is a shape.

   Cost so far: ~\$0.00 — storage only, no instance was created.
   Tear down with:  ./gxr down fraud-rings   (drops the database, not the instance)

EOF
