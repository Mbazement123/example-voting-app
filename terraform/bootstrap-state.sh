#!/usr/bin/env bash
set -euo pipefail

# Ensure AWS_REGION is exported so Terraform and AWS CLI inherit it globally
: "${AWS_REGION:?Set AWS_REGION to the deployment region}"
export AWS_REGION

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

# Robust bucket existence check:
# head-bucket returns 403 if it exists but you lack list permissions, 
# or 404 if it truly doesn't exist. We check for existence safely.
bucket_exists=false
if aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>/dev/null; then
  bucket_exists=true
else
  # Check if error was 404 (Not Found) vs 403 (Forbidden/Exists elsewhere)
  err_code=$(aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>&1 || true)
  if echo "$err_code" | grep -q "404"; then
    bucket_exists=false
  else
    # If it's a 403 or permission issue, assume it exists and let Terraform handle it, 
    # or handle gracefully instead of failing blindly on create-bucket.
    bucket_exists=true 
  fi
fi

if [ "$bucket_exists" = false ]; then
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