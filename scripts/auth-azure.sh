#!/usr/bin/env bash
# Authenticate to Azure using the service principal credentials from wings/.env.
# Can be run standalone or sourced by other scripts.
#
# Usage:
#   ./scripts/auth-azure.sh
#   source ./scripts/auth-azure.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -a
source "$SCRIPT_DIR/../../wings/.env"
set +a

export ARM_CLIENT_ID=$AZURE_CLIENT_ID
export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
export ARM_TENANT_ID=$AZURE_TENANT_ID
export ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID

az login --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"

echo "Authenticated as service principal $AZURE_CLIENT_ID"
