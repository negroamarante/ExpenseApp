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
