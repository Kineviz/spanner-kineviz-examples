#!/usr/bin/env bash
# Check everything before creating anything. Creates nothing, bills nothing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=preflight
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Preflight — checking prerequisites (nothing will be created)"

[ -f "$DEMO_DIR/.env" ] || die "No .env found." \
  "cp .env.example .env, set GCP_PROJECT and SPANNER_INSTANCE, then re-run. Nothing has been created yet."
load_env "$DEMO_DIR"
require_env GCP_PROJECT SPANNER_INSTANCE SPANNER_DATABASE SPANNER_GRAPH \
            FRAUD_CLIENTS FRAUD_TRANSACTIONS FRAUD_SEED

[ "$GCP_PROJECT" != "your-project-id" ] || die "GCP_PROJECT is still the placeholder." \
  "Set a real project ID in .env. Nothing has been created yet."
[ "$SPANNER_INSTANCE" != "your-instance" ] || die "SPANNER_INSTANCE is still the placeholder." \
  "Set a real instance in .env. List them: gcloud spanner instances list --project=$GCP_PROJECT"

require_cli gcloud python3

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "No active gcloud credentials." \
         "Run 'gcloud auth login' then 'gcloud auth application-default login', and re-run."
ok "gcloud authenticated"

gcloud projects describe "$GCP_PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot access project '$GCP_PROJECT'." "Check the ID in .env."
ok "project $GCP_PROJECT reachable"

gcloud services list --enabled --project="$GCP_PROJECT" \
  --filter='config.name:spanner.googleapis.com' --format='value(config.name)' 2>/dev/null | grep -q . \
  || die "The Spanner API is not enabled on '$GCP_PROJECT'." \
         "Run: gcloud services enable spanner.googleapis.com --project=$GCP_PROJECT"
ok "Spanner API enabled"

# The instance must already exist. Creating one is the expensive, slow step and
# this demo deliberately does not do it on your behalf.
if ! gcloud spanner instances describe "$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
       --format='value(state)' >/dev/null 2>&1; then
  die "Spanner instance '$SPANNER_INSTANCE' not found in $GCP_PROJECT." \
      "$(cat <<EOF
this demo adds a DATABASE to an instance you already run — it will not create one,
    because an instance bills continuously whether you query it or not.
      list yours:      gcloud spanner instances list --project=$GCP_PROJECT
      no instance yet: a free trial instance is 90 days at no charge —
                       https://docs.cloud.google.com/spanner/docs/free-trial-instance
EOF
)"
fi
ok "instance $SPANNER_INSTANCE exists"
dim "this demo adds a database to it; teardown drops only that database, never the instance"

if gcloud spanner databases describe "$SPANNER_DATABASE" --instance="$SPANNER_INSTANCE" \
     --project="$GCP_PROJECT" >/dev/null 2>&1; then
  warn "Database $SPANNER_DATABASE already exists — setup will reuse it and replace its rows."
fi

require_kineviz_desktop "0.17.1"
ok "preflight passed — nothing has been created yet"
info "Next: ./scripts/setup.sh (creates database ${SPANNER_DATABASE}; storage-only cost)"
