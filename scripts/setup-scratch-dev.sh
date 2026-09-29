#!/usr/bin/env bash
# Deploy force-app to a scratch org (skips Email Service), assign permset,
# and optionally seed dummy data for the current month.
#
# Usage:
#   ./scripts/setup-scratch-dev.sh
#   ./scripts/setup-scratch-dev.sh --target-org expenseapp-spending --seed
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET_ORG=""
SEED=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org)
      TARGET_ORG="${2:-}"
      shift 2
      ;;
    --seed)
      SEED=true
      shift
      ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SF_TARGET=()
if [[ -n "$TARGET_ORG" ]]; then
  SF_TARGET=(--target-org "$TARGET_ORG")
fi

echo "==> Verifying target is a scratch org..."
ORG_JSON="$(sf org display "${SF_TARGET[@]}" --json)"
ORG_LIST_JSON="$(sf org list --json)"
python3 -c '
import json, sys
org_payload = json.loads(sys.argv[1])
list_payload = json.loads(sys.argv[2])
if org_payload.get("status") not in (0, None):
    sys.stderr.write("Could not read the target org.\n")
    sys.exit(1)
username = (org_payload.get("result") or {}).get("username")
if not username:
    sys.stderr.write("Org display did not include a username.\n")
    sys.exit(1)
scratch_orgs = (list_payload.get("result") or {}).get("scratchOrgs") or []
if not any(org.get("username") == username for org in scratch_orgs):
    sys.stderr.write(
        "This script deploys source and can seed dummy financial data; it "
        "only runs against scratch orgs. Resolved target (" + username +
        ") is not a scratch org.\n"
    )
    sys.exit(1)
' "$ORG_JSON" "$ORG_LIST_JSON"

echo "==> Deploying source (excluding emailservices)..."
DEPLOY_DIRS=()
for dir in force-app/main/default/*/; do
  name=$(basename "$dir")
  if [ "$name" != "emailservices" ]; then
    DEPLOY_DIRS+=(--source-dir "$dir")
  fi
done
sf project deploy start "${SF_TARGET[@]}" "${DEPLOY_DIRS[@]}" --wait 30

echo "==> Assigning permission set..."
sf org assign permset "${SF_TARGET[@]}" --name Presupuesto_Familiar_Acceso

if [[ "$SEED" == true ]]; then
  echo "==> Seeding current-month dummy data..."
  sf apex run "${SF_TARGET[@]}" --file scripts/apex/seed-scratch-month.apex
fi

echo "==> Done. Open the org with:"
echo "    sf org open ${SF_TARGET[*]} --path /lightning/app/c__Presupuesto_Familiar"
