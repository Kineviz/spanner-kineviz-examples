#!/usr/bin/env bash
# Drop the database this demo created — and NOTHING else.
#
# Specifically NOT the instance. An instance can hold databases belonging to
# other people or other work; deleting one to clean up a demo would be
# destroying somebody else's data to save a few cents. The instance is also the
# thing that costs money, so whether to keep it is a decision for its owner,
# not for a teardown script.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=teardown
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Teardown — removing what this demo created"
load_env "$DEMO_DIR"
require_env GCP_PROJECT SPANNER_INSTANCE SPANNER_DATABASE

if gcloud spanner databases describe "$SPANNER_DATABASE" --instance="$SPANNER_INSTANCE" \
     --project="$GCP_PROJECT" >/dev/null 2>&1; then
  gcloud spanner databases delete "$SPANNER_DATABASE" \
    --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" --quiet \
    || die "Failed to delete database $SPANNER_DATABASE." \
           "Delete it by hand: gcloud spanner databases delete $SPANNER_DATABASE --instance=$SPANNER_INSTANCE"
  ok "deleted database $SPANNER_DATABASE"
else
  info "database $SPANNER_DATABASE does not exist — nothing to delete"
fi

rm -rf "$DEMO_DIR/data/generated" "$DEMO_DIR/.verified_rows"
ok "removed locally generated data"
info "Instance $SPANNER_INSTANCE was NOT touched — it may hold other databases."
dim "it is also what bills continuously; delete it yourself if it was only for this demo"
