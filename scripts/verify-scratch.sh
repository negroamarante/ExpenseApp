#!/usr/bin/env bash
# Creates a throwaway scratch org, deploys force-app, runs Apex + Jest tests,
# and deletes the scratch org when it's done (pass or fail).
set -euo pipefail

DEVHUB_ALIAS="${DEVHUB_ALIAS:-expenseApp}"
SCRATCH_ALIAS="expenseapp-ci-$(date +%s)"
DURATION_DAYS="${SCRATCH_DURATION_DAYS:-1}"

cleanup() {
  echo "==> Deleting scratch org ${SCRATCH_ALIAS}..."
  sf org delete scratch --target-org "$SCRATCH_ALIAS" --no-prompt || true
}
trap cleanup EXIT

echo "==> Creating scratch org (dev hub: ${DEVHUB_ALIAS})..."
sf org create scratch \
  --target-dev-hub "$DEVHUB_ALIAS" \
  --definition-file config/project-scratch-def.json \
  --alias "$SCRATCH_ALIAS" \
  --duration-days "$DURATION_DAYS" \
  --set-default \
  --wait 15

echo "==> Deploying source..."
sf project deploy start --target-org "$SCRATCH_ALIAS" --source-dir force-app --wait 30

echo "==> Assigning permission set..."
sf org assign permset --target-org "$SCRATCH_ALIAS" --name Presupuesto_Familiar_Acceso

echo "==> Running Apex tests..."
sf apex run test \
  --target-org "$SCRATCH_ALIAS" \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 30

echo "==> Running Jest tests..."
npm ci
npm run test:unit

echo "==> All checks passed."
