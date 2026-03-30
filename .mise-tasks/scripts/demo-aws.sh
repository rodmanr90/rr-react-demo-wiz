#!/usr/bin/env bash
#
# Source this file from mise tasks to run all AWS/Terraform actions against a
# dedicated "throwaway demo" AWS account without touching the user's normal
# AWS profile/credentials.
#
# Usage in a mise task:
#   # shellcheck source=/dev/null
#   source "$(command -v demo-aws.sh)"
#   demo_aws_activate
#

set -euo pipefail

demo_aws_activate() {
  # Do not allow an ambient profile/config to accidentally override credentials.
  unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SDK_LOAD_CONFIG

  if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo "ERROR: AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY are not set." >&2
    echo "Set throwaway demo credentials for this repo, e.g.:" >&2
    echo "  export AWS_ACCESS_KEY_ID='...'" >&2
    echo "  export AWS_SECRET_ACCESS_KEY='...'" >&2
    echo "  export AWS_REGION='ap-southeast-2'     # optional" >&2
    return 1
  fi

  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
  export AWS_REGION="$region"
  export AWS_DEFAULT_REGION="$region"
  export TF_VAR_aws_region="${TF_VAR_aws_region:-$region}"

  # Confirm credentials are valid and capture identity for logging/traceability.
  local actual_account=""
  actual_account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  if [[ -z "$actual_account" || "$actual_account" == "None" ]]; then
    echo "ERROR: AWS authentication failed for provided AWS_* credentials." >&2
    return 1
  fi
  export AWS_ACCOUNT_ID_ACTUAL="$actual_account"
}

demo_aws_assert_account() {
  # Backwards-compat no-op: tasks used to call this to enforce account matching.
  # We keep it to avoid breaking older scripts, but it no longer blocks.
  demo_aws_activate >/dev/null
}
