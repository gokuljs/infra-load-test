#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo 'Usage: bash scripts/publish-fargate-images.sh <release-tag> [nodejs|go]' >&2
  exit 2
fi

release_tag=$1
case ${2:-} in
  nodejs|go) services=("$2") ;;
  '') services=(nodejs go) ;;
  *) echo 'Service must be nodejs or go.' >&2; exit 2 ;;
esac

: "${TF_VAR_aws_region:?Set TF_VAR_aws_region to the Fargate registry region}"
: "${TF_VAR_aws_account_id:?Set TF_VAR_aws_account_id to the Fargate registry account}"

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repositories=$(terraform -chdir="$repo_root/infra/ecs-fargate/registry" output -json repository_urls)
digests='{}'

for service in "${services[@]}"; do
  repository=$(jq -er --arg name "$service" '.[$name] | select(type == "string" and length > 0)' <<< "$repositories")
  digest=$(APP_AWS_REGION="$TF_VAR_aws_region" \
    APP_AWS_ACCOUNT_ID="$TF_VAR_aws_account_id" \
    APP_ECR_REPOSITORY_URL="$repository" APP_IMAGE_TAG="$release_tag" \
    APP_IMAGE_CONTEXT="$repo_root/$service" \
    bash "$repo_root/scripts/publish-image.sh" --digest-only)
  printf 'Published or verified %s:%s at %s\n' "$repository" "$release_tag" "$digest" >&2
  digests=$(jq -c --arg name "$service" --arg digest "$digest" '. + {($name): $digest}' <<< "$digests")
done

printf '%s\n' "$digests"
