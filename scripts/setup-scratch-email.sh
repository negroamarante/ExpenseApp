#!/usr/bin/env bash
# Deploys the budget Email Service using the scratch org user as runAsUser,
# then prints the inbound address you can forward invoices to.
#
# Usage:
#   ./scripts/setup-scratch-email.sh
#   ./scripts/setup-scratch-email.sh --target-org my-scratch
#
# Optional:
#   AUTHORIZED_SENDERS="you@example.com"  restrict who can send (default: anyone)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET_ORG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org)
      TARGET_ORG="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
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

ORG_JSON="$(sf org display "${SF_TARGET[@]}" --json)"
USERNAME="$(python3 -c '
import json, sys
payload = json.load(sys.stdin)
result = payload.get("result") or {}
if payload.get("status") not in (0, None):
    sys.stderr.write("Could not read the target org.\n")
    sys.exit(1)
username = result.get("username")
if not username:
    sys.stderr.write("Org display did not include a username.\n")
    sys.exit(1)
print(username)
' <<<"$ORG_JSON")"

# `sf org display --json` has no `result.isScratch` field, so verify the
# resolved username is actually a scratch org via `sf org list`.
ORG_LIST_JSON="$(sf org list --json)"
python3 -c '
import json, sys
payload = json.load(sys.stdin)
username = sys.argv[1]
scratch_orgs = (payload.get("result") or {}).get("scratchOrgs") or []
if not any(org.get("username") == username for org in scratch_orgs):
    sys.stderr.write(
        "This script is only for scratch orgs. The Email Service in force-app "
        "already targets the production user.\n"
    )
    sys.exit(1)
' "$USERNAME" <<<"$ORG_LIST_JSON"

echo "==> Scratch user: ${USERNAME}"
echo "==> Generating Email Service metadata..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
EMAIL_DIR="${TMPDIR}/emailservices"
mkdir -p "$EMAIL_DIR"

AUTHORIZED_SENDERS="${AUTHORIZED_SENDERS:-}"
python3 - "$EMAIL_DIR" "$USERNAME" "$AUTHORIZED_SENDERS" <<'PY'
import sys
import xml.etree.ElementTree as ET

email_dir, username, authorized_senders = sys.argv[1], sys.argv[2], sys.argv[3]
ns = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", ns)

def el(tag, text=None):
    node = ET.Element(f"{{{ns}}}{tag}")
    if text is not None:
        node.text = text
    return node

root = el("EmailServicesFunction")
fields = [
    ("apexClass", "BudgetEmailHandler"),
    ("attachmentOption", "All"),
    ("authenticationFailureAction", "Discard"),
    ("authorizationFailureAction", "Discard"),
]
for name, value in fields:
    root.append(el(name, value))

address = el("emailServicesAddresses")
if authorized_senders:
    address.append(el("authorizedSenders", authorized_senders))
address.append(el("developerName", "Presupuesto"))
address.append(el("isActive", "true"))
address.append(el("localPart", "budget_invoice_processor"))
address.append(el("runAsUser", username))
root.append(address)

for name, value in [
    ("functionInactiveAction", "Discard"),
    ("functionName", "Budget Invoice Processor"),
    ("isActive", "true"),
    ("isAuthenticationRequired", "false"),
    ("isErrorRoutingEnabled", "false"),
    ("isTextAttachmentsAsBinary", "false"),
    ("isTlsRequired", "false"),
    ("overLimitAction", "Discard"),
]:
    root.append(el(name, value))

tree = ET.ElementTree(root)
ET.indent(tree, space="    ")
path = f"{email_dir}/Budget Invoice Processor.xml-meta.xml"
tree.write(path, encoding="UTF-8", xml_declaration=True)
PY

echo "==> Deploying Email Service..."
sf project deploy start \
  "${SF_TARGET[@]}" \
  --source-dir "$EMAIL_DIR" \
  --wait 10

echo "==> Looking up the inbound address..."
QUERY_JSON="$(sf data query "${SF_TARGET[@]}" --json --query \
  "SELECT LocalPart, EmailDomainName, AuthorizedSenders, IsActive FROM EmailServicesAddress WHERE LocalPart = 'budget_invoice_processor'")"

python3 -c '
import json, sys
payload = json.loads(sys.argv[1])
records = (payload.get("result") or {}).get("records") or []
if not records:
    sys.stderr.write(
        "Email Service deployed, but no EmailServicesAddress was found.\n"
    )
    sys.exit(1)
row = records[0]
local_part = row.get("LocalPart") or ""
domain = row.get("EmailDomainName") or ""
senders = row.get("AuthorizedSenders") or "(anyone)"
active = row.get("IsActive")
print()
print("Forward the invoice/summary to:")
print(f"  {local_part}@{domain}")
print(f"Authorized senders: {senders}")
print(f"Active: {active}")
print()
print("Needs the Gemini key in Api_Key_Store (org default) to parse the mail.")
' "$QUERY_JSON"
