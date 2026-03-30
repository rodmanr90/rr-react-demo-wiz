# Secrets Setup Guide

This guide defines what each SE must configure before running workflows.

## Important

- Secrets and variables do **not** transfer when creating a new repo from template.
- Every SE must configure their own GitHub repo settings.
- Local `secrets.env` is gitignored and also does not come from clone.

## Wiz VCS Integration (Required for Code-to-Cloud)

Before deploying with `enable_wiz=true`, ensure your GitHub repo is added to the Wiz VCS integration in your tenant (**Settings → Integrations → Version Control**). Without this, Wiz cannot scan the `backend.tf` files that link Terraform state to deployed cloud resources, and IaC code-to-cloud mapping will not work.

## Where to Set Values

- GitHub UI: `Settings -> Secrets and variables -> Actions`
- Local terminal: copy `secrets.env.example` to `secrets.env`, fill values, then:

```bash
set -a; source secrets.env; set +a
```

## Scenario Matrix

### 1) No-Wiz smoke (`enable_wiz=false`)

Required:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

Not required:
- `WIZ_CLIENT_ID`, `WIZ_CLIENT_SECRET`
- `TF_VAR_wiz_tenant_id`, `TF_VAR_wiz_trusted_arn`
- `TF_VAR_tenant_image_pull_username`, `TF_VAR_tenant_image_pull_password`

Optional:
- `TF_VAR_allowed_cidrs` (needed for direct browser access and for adding extra allow-list CIDRs, including scanner CIDRs if required)

### 2) Full Wiz demo (`enable_wiz=true`)

Required:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `WIZ_CLIENT_ID`
- `WIZ_CLIENT_SECRET`
- `TF_VAR_wiz_tenant_id`
- `TF_VAR_wiz_trusted_arn`
- `TF_VAR_wiz_client_environment` (usually `prod`)

Strongly recommended for healthy sensor/image pulls:
- `TF_VAR_tenant_image_pull_username`
- `TF_VAR_tenant_image_pull_password`

Recommended for stronger mapping:
- `WIZ_CLI_CLIENT_ID`
- `WIZ_CLI_CLIENT_SECRET`

Optional:
- `TF_VAR_allowed_cidrs` (required for direct browser access from your laptop; can also include additional scanner CIDRs)

## Clarification on "required" values

- `TF_VAR_wiz_trusted_arn` and `TF_VAR_wiz_tenant_id` are required if you expect the AWS Wiz connector path to be created and fully wired for IaC/cloud correlation.
- `TF_VAR_tenant_image_pull_username` / `TF_VAR_tenant_image_pull_password` are required if you expect Wiz sensor images to pull successfully and sensor telemetry to be fully healthy.
  - Without these, deploy can still complete, but sensor pods may fail image pull and runtime coverage will be degraded.

## Suggested GitHub Actions configuration

Set these as **Secrets**:
- `AWS_SECRET_ACCESS_KEY`
- `WIZ_CLIENT_SECRET`
- `TF_VAR_tenant_image_pull_password`

Set these as **Secrets or Variables** (org preference):
- `AWS_ACCESS_KEY_ID`
- `AWS_REGION`
- `WIZ_CLIENT_ID`
- `WIZ_CLI_CLIENT_ID`
- `WIZ_CLI_CLIENT_SECRET`
- `TF_VAR_wiz_tenant_id`
- `TF_VAR_wiz_trusted_arn`
- `TF_VAR_wiz_client_environment`
- `TF_VAR_tenant_image_pull_username`
- `TF_VAR_allowed_cidrs`

NetworkPolicy note:
- Effective allow-list = default scanner CIDRs from `TF_VAR_dynamic_scanner_ipv4s_develop` + `TF_VAR_allowed_cidrs`.
- If your tenant scanner CIDRs differ, override `TF_VAR_dynamic_scanner_ipv4s_develop` and/or add scanner CIDRs in `TF_VAR_allowed_cidrs`.
