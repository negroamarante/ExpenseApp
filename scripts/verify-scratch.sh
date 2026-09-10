#!/usr/bin/env bash
# Creates a throwaway scratch org, deploys force-app, runs Apex + Jest tests,
# and deletes the scratch org when it's done (pass or fail).
set -euo pipefail

DEVHUB_ALIAS="${DEVHUB_ALIAS:-expenseApp}"
SCRATCH_ALIAS="expenseapp-ci-$(date +%s)"
DURATION_DAYS="${SCRATCH_DURATION_DAYS:-1}"

cleanup() {
  echo "==> Deleting scratch org ${SCRATCH_ALIAS}..."
  sf org delete scratch -o "$SCRATCH_ALIAS" --no-prompt || true
}
trap cleanup EXIT

echo "==> Creating scratch org (dev hub: ${DEVHUB_ALIAS})..."
sf org create scratch \
  -v "$DEVHUB_ALIAS" \
  -f config/project-scratch-def.json \
  -a "$SCRATCH_ALIAS" \
  -d "$DURATION_DAYS" \
  --set-default

echo "==> Deploying source..."
sf project deploy start -o "$SCRATCH_ALIAS" -d force-app --wait 30

echo "==> Assigning permission set..."
sf org assign permset -o "$SCRATCH_ALIAS" -n Presupuesto_Familiar_Acceso

echo "==> Running Apex tests..."
sf apex run test \
  -o "$SCRATCH_ALIAS" \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 30

echo "==> Running Jest tests..."
npm ci
npm run test:unit

echo "==> All checks passed."
