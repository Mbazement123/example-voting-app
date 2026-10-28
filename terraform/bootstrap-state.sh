#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION to the deployment region}"

account_id="$(aws sts get-caller-identity --query Account --output text)"
TF_STATE_BUCKET="example-voting-app-terraform-state-${account_id}-${AWS_REGION}"
state_key="example-voting-app/bootstrap/terraform.tfstate"
terraform_dir="terraform/state"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'TF_STATE_BUCKET=%s\n' "$TF_STATE_BUCKET" >> "$GITHUB_ENV"
fi

backend_config=(
  "-backend-config=bucket=$TF_STATE_BUCKET"
  "-backend-config=key=$state_key"
  "-backend-config=region=$AWS_REGION"
  "-backend-config=encrypt=true"
  "-backend-config=use_lockfile=true"
)

if ! aws s3api head-bucket \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  create_bucket_args=(--bucket "$TF_STATE_BUCKET" --region "$AWS_REGION")
  if [[ "$AWS_REGION" != "us-east-1" ]]; then
    create_bucket_args+=(--create-bucket-configuration "LocationConstraint=$AWS_REGION")
  fi
  aws s3api create-bucket "${create_bucket_args[@]}"
fi

terraform -chdir="$terraform_dir" init -reconfigure -input=false "${backend_config[@]}"

if ! aws s3api head-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "$state_key" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  terraform -chdir="$terraform_dir" import \
    -input=false \
    -var="aws_region=$AWS_REGION" \
    aws_s3_bucket.state "$TF_STATE_BUCKET"
fi

terraform -chdir="$terraform_dir" apply \
  -input=false \
  -auto-approve \
  -var="aws_region=$AWS_REGION"
