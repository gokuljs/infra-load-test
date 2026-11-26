#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

: "${APP_ECR_REPOSITORY_URL:?Set APP_ECR_REPOSITORY_URL}"
: "${APP_AWS_REGION:?Set APP_AWS_REGION}"
: "${APP_AWS_ACCOUNT_ID:?Set APP_AWS_ACCOUNT_ID}"
: "${APP_IMAGE_TAG:?Set APP_IMAGE_TAG}"
: "${APP_IMAGE_DIGEST_PARAMETER:?Set APP_IMAGE_DIGEST_PARAMETER}"

if [[ ! $APP_ECR_REPOSITORY_URL =~ ^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com(\.cn)?/([a-z0-9._/-]+)$ ]]; then
  echo "Expected APP_ECR_REPOSITORY_URL to name a private ECR repository." >&2
  exit 1
fi
registry_account=${BASH_REMATCH[1]}
registry_region=${BASH_REMATCH[2]}
repository_name=${BASH_REMATCH[4]}
registry=${APP_ECR_REPOSITORY_URL%%/*}

if [[ $registry_account != "$APP_AWS_ACCOUNT_ID" || $registry_region != "$APP_AWS_REGION" ]]; then
  echo "The ECR repository must match the configured AWS account and region." >&2
  exit 1
fi
if [[ ! $APP_IMAGE_TAG =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "Expected APP_IMAGE_TAG to be a valid Docker tag." >&2
  exit 1
fi

caller_account=$(aws sts get-caller-identity --region "$APP_AWS_REGION" --query Account --output text)
if [[ $caller_account != "$APP_AWS_ACCOUNT_ID" ]]; then
  echo "The active AWS CLI credentials must belong to the ECR registry account." >&2
  exit 1
fi

lookup_image() {
  aws ecr batch-get-image --region "$APP_AWS_REGION" \
    --registry-id "$registry_account" --repository-name "$repository_name" \
    --image-ids "imageTag=$APP_IMAGE_TAG" \
    --query '[images[0].imageId.imageDigest, failures[0].failureCode]' --output text
}

image_ref="$APP_ECR_REPOSITORY_URL:$APP_IMAGE_TAG"
image_result=$(lookup_image)
IFS=$'\t' read -r digest failure_code <<< "$image_result"
if [[ $failure_code == ImageNotFound ]]; then
  repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  aws ecr get-login-password --region "$APP_AWS_REGION" |
    docker login --username AWS --password-stdin "$registry"
  docker buildx build --platform linux/amd64 --provenance=false \
    --tag "$image_ref" --push "$repo_root/nodejs"

  image_result=$(lookup_image)
  IFS=$'\t' read -r digest failure_code <<< "$image_result"
fi

if [[ $failure_code != None || ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "Could not verify the ECR digest for $image_ref (lookup result: $image_result)." >&2
  exit 1
fi

aws ssm put-parameter --region "$APP_AWS_REGION" \
  --name "$APP_IMAGE_DIGEST_PARAMETER" --type String --value "$digest" --overwrite >/dev/null
printf 'Image %s has digest %s. Updated %s.\n' "$image_ref" "$digest" "$APP_IMAGE_DIGEST_PARAMETER"
