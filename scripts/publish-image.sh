#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

: "${APP_ECR_REPOSITORY_URL:?Set APP_ECR_REPOSITORY_URL}"
: "${APP_AWS_REGION:?Set APP_AWS_REGION}"
: "${APP_AWS_ACCOUNT_ID:?Set APP_AWS_ACCOUNT_ID}"
: "${APP_IMAGE_TAG:?Set APP_IMAGE_TAG}"

case $#:${1:-} in
  0:)
    : "${APP_IMAGE_DIGEST_PARAMETER:?Set APP_IMAGE_DIGEST_PARAMETER}"
    ;;
  1:--digest-only)
    : "${APP_IMAGE_CONTEXT:?Set APP_IMAGE_CONTEXT}"
    # Keep machine-readable output separate from Docker and AWS diagnostics.
    exec 3>&1 1>&2
    ;;
  *)
    echo 'Usage: bash scripts/publish-image.sh [--digest-only]' >&2
    exit 2
    ;;
esac

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
  if ! command -v docker >/dev/null; then
    echo "Install Docker with Buildx, start Docker, and retry publishing." >&2
    exit 1
  fi
  if ! docker buildx version >/dev/null; then
    echo "Install Docker Buildx (included with Docker Desktop) and retry publishing." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    if [[ $(uname -s) != Darwin || -n ${DOCKER_HOST:-} ]]; then
      echo "The configured Docker engine is unavailable. Restore it, wait for 'docker info' to succeed, and retry publishing." >&2
      exit 1
    fi

    docker_context=$(docker context show)
    docker_endpoint=$(docker context inspect "$docker_context" --format '{{.Endpoints.docker.Host}}')
    if [[ ( $docker_context != desktop-linux && $docker_context != default ) || $docker_endpoint != unix://* ]]; then
      echo "Docker context '$docker_context' is unavailable. Restore its connection, wait for 'docker info' to succeed, and rerun terraform apply." >&2
      exit 1
    fi

    echo "Starting Docker Desktop and waiting up to 120 seconds for startup."
    if ! docker desktop start --timeout 120; then
      echo "Docker Desktop could not start. Open it with 'open -a Docker', wait for 'docker info' to succeed, and rerun terraform apply." >&2
      exit 1
    fi
    if ! docker info >/dev/null; then
      echo "Docker Desktop startup finished but its engine is unavailable. Check the Docker Desktop status and Docker context, wait for 'docker info' to succeed, and rerun terraform apply." >&2
      exit 1
    fi
  fi

  repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  build_context="$repo_root/nodejs"
  if [[ ${1:-} == --digest-only ]]; then
    build_context="$APP_IMAGE_CONTEXT"
  fi
  aws ecr get-login-password --region "$APP_AWS_REGION" |
    docker login --username AWS --password-stdin "$registry"
  docker buildx build --platform linux/amd64 --provenance=false \
    --tag "$image_ref" --push "$build_context"

  image_result=$(lookup_image)
  IFS=$'\t' read -r digest failure_code <<< "$image_result"
fi

if [[ $failure_code != None || ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "Could not verify the ECR digest for $image_ref (lookup result: $image_result)." >&2
  exit 1
fi

if [[ ${1:-} == --digest-only ]]; then
  printf '%s\n' "$digest" >&3
else
  aws ssm put-parameter --region "$APP_AWS_REGION" \
    --name "$APP_IMAGE_DIGEST_PARAMETER" --type String --value "$digest" --overwrite >/dev/null
  printf 'Image %s has digest %s. Updated %s.\n' "$image_ref" "$digest" "$APP_IMAGE_DIGEST_PARAMETER"
fi
