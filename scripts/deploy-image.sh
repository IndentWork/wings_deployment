#!/usr/bin/env bash
# Deploy the Wings image to an environment's App Service slots.
# Mirrors the blue-green deploy logic in _apply-env.yml.
#
# Usage:
#   ./scripts/deploy-image.sh <environment>
#
# Examples:
#   ./scripts/deploy-image.sh sb
#   ./scripts/deploy-image.sh dev

set -euo pipefail

ENV=${1:-}

if [ -z "$ENV" ]; then
  echo "Usage: $0 <environment>"
  echo "       environment: dev | sb | qa | prod"
  exit 1
fi

ENV_DIR="environments/$ENV"

if [ ! -d "$ENV_DIR" ]; then
  echo "Error: environment '$ENV' not found at $ENV_DIR"
  exit 1
fi

echo "Reading Terraform outputs for $ENV..."
cd "$ENV_DIR"

VERSION=$(terraform output -raw image_version)
APP_NAME=$(terraform output -raw web_app_name)
RG=$(terraform output -raw resource_group_name)
IMAGE="acriwwings01.azurecr.io/wings:$VERSION"

cd - > /dev/null

echo "App:     $APP_NAME"
echo "RG:      $RG"
echo "Image:   $IMAGE"
echo ""

# --- Detect deploy mode ---

current=$(az webapp config container show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[?name=='DOCKER_CUSTOM_IMAGE_NAME'].value | [0]" -o tsv 2>/dev/null || echo "")

current_image=$(echo "$current" | sed -E 's|^https?://||')

current_staging=$(az webapp config container show \
  --name "$APP_NAME" --resource-group "$RG" \
  --slot staging \
  --query "[?name=='DOCKER_CUSTOM_IMAGE_NAME'].value | [0]" -o tsv 2>/dev/null || echo "")

current_staging_image=$(echo "$current_staging" | sed -E 's|^https?://||')

echo "Current production image: ${current_image:-<none>}"
echo "Current staging image:    ${current_staging_image:-<none>}"
echo "Intended image:           $IMAGE"
echo ""

if [ -z "$current_image" ]; then
  echo "Mode: bootstrap — setting image on production directly"
  az webapp config container set \
    --name "$APP_NAME" --resource-group "$RG" \
    --container-image-name "$IMAGE"

elif [ -z "$current_staging_image" ]; then
  echo "Mode: bootstrap-staging — setting image on both slots directly"
  az webapp config container set \
    --name "$APP_NAME" --resource-group "$RG" \
    --slot staging \
    --container-image-name "$IMAGE"
  az webapp config container set \
    --name "$APP_NAME" --resource-group "$RG" \
    --container-image-name "$IMAGE"

elif [ "$current_image" = "$IMAGE" ]; then
  echo "Mode: skip — production already runs $IMAGE"

else
  echo "Mode: swap — deploying to staging, health checking, then swapping"
  az webapp config container set \
    --name "$APP_NAME" --resource-group "$RG" \
    --slot staging \
    --container-image-name "$IMAGE"

  STAGING_URL="https://${APP_NAME}-staging.azurewebsites.net"
  echo "Health checking $STAGING_URL ..."
  for i in $(seq 1 30); do
    code=$(curl -sS --max-time 30 -o /dev/null -w "%{http_code}" "$STAGING_URL/" || echo "000")
    echo "Attempt $i: HTTP $code"
    if [ "$code" = "200" ]; then
      echo "Staging healthy — swapping"
      az webapp deployment slot swap \
        --name "$APP_NAME" --resource-group "$RG" \
        --slot staging --target-slot production
      echo "Swap complete. Production is now running $IMAGE"
      exit 0
    fi
    sleep 10
  done
  echo "Error: staging never returned 200"
  exit 1
fi

echo "Done."
