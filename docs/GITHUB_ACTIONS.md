# GitHub Actions (CI/CD)

See `docs/SECRETS_SETUP.md` for scenario-based required secrets/variables.

This repo supports four GitHub Actions workflows:

- `CI Validation (Fmt + Terraform Validate)` (`.github/workflows/ci.yml`): validation-only checks on PR/push, no deploy/destroy
- `Demo Lifecycle (Deploy + Optional Destroy)` (`.github/workflows/demo-cycle.yml`): deploy, validate, optional destroy
- `Demo Attack Simulation (Defend Telemetry)` (`.github/workflows/attack-sim.yml`): runtime/telemetry simulation against an existing environment
- `Demo Banner Toggle (Visual Proof)` (`.github/workflows/attack-banner.yml`): set/reset app banner via runner-side port-forward

## Workflow At A Glance

- `CI Validation (Fmt + Terraform Validate)`: Use for code quality and Terraform validation only.
- `Demo Lifecycle (Deploy + Optional Destroy)`: Main operator workflow for `deploy -> verify -> (optional) destroy`.
- `Demo Attack Simulation (Defend Telemetry)`: Use after deploy to generate runtime demo telemetry.
- `Demo Banner Toggle (Visual Proof)`: Quick visual app-change demo without full exploit simulation.

## How To Run Workflows (GitHub UI)

Use this click path for all manual runs:
1. Open your repo in GitHub.
2. Click `Actions`.
3. Choose the workflow (`Demo Lifecycle`, `Demo Attack Simulation`, or `Demo Banner Toggle`).
4. Click `Run workflow`.
5. Select branch (usually `main`), set inputs, then click `Run workflow`.

Example:

![GitHub Actions Run Workflow Example](docs/screenshots/github-run-workflow.png)

## Repo Setup In Org (Template Workflow)

Use this repo as a template and create your own demo repo in the org:

```bash
gh repo create <org>/<your-demo-repo> --private --template <template-owner>/<template-repo>
```

GitHub UI:
- Open the template repo.
- Click **Use this template**.
- Create your new repo in your org.

## Workflow: `CI Validation (Fmt + Terraform Validate)`

File: `.github/workflows/ci.yml`

Runs:
- `terraform fmt -check -recursive`
- `terraform validate` for `infrastructure/backends`
- `terraform validate` for `infrastructure/demo` (only if `*.tf` files exist in that directory on the branch)

No AWS or Wiz credentials are required. This workflow never deploys infrastructure.

## Workflow: `Demo Lifecycle (Deploy + Optional Destroy)`

File: `.github/workflows/demo-cycle.yml`

Triggered manually via `workflow_dispatch`. It:
1. Installs tooling via `mise`
2. Bootstraps (or reuses) a stable S3 backend (for Wiz code-to-cloud mapping)
3. Runs `mise run deploy-demo` (optionally `--skip-image` and `--skip-verify`)
4. Verifies Kubernetes readiness (no public NLB curl required)
5. Runs a Wiz Code scan (`wizcli scan dir .`) if Wiz CLI secrets are set
6. Runs a Wiz container image scan + tag (cloud-to-code mapping) if the image was built and Wiz CLI secrets are set
7. Runs `mise run destroy-demo --no-dry-run` in an `always()` block **only when** `destroy=true`

### destroy behavior

- `destroy=false` keeps the environment running for live demos and validation follow-up.
- `destroy=true` tears down the environment at end of run.
- The workflow now defaults `destroy=false` for demo-first operation.

### enable_wiz toggle

The workflow input `enable_wiz` controls which Terraform root is used:

- `enable_wiz=true`: `infrastructure/demo` (includes Wiz provider/resources)
- `enable_wiz=false`: `infrastructure/demo-nowiz` (no Wiz provider; no Wiz credentials required)

Optional:
- If you set the workflow input `destroy_backend=true`, it will run `mise run destroy-demo --no-dry-run --destroy-backend` to also delete the shared S3 backend bucket + SSM parameter.
  - This temporarily breaks Wiz code-to-cloud mapping until the backend (and state) exists again.
  - `iac_config.wiz` stays valid when destroying/recreating the backend in the same AWS account/region (bucket name is deterministic). If you switch accounts/regions, regenerate and commit `iac_config.wiz`.

Note: The S3 backend is intentionally retained (both locally and in CI) because Wiz code-to-cloud mapping depends on Wiz being able to read Terraform state from S3. Use `mise run destroy-demo --no-dry-run --destroy-backend` only when you explicitly want to tear down the backend too (and accept that Wiz mapping will stop working until recreated).

Note: `mise run deploy-demo` automatically skips the public NLB curl verification when `CI=true` or `GITHUB_ACTIONS=true`.

### Public IP / NetworkPolicy note (local vs CI)

- `mise run get-my-ip` is intended for **local** demo operators. It detects your current public IP and sets `TF_VAR_allowed_cidrs=["<your-ip>/32"]` so the app NetworkPolicy allows you to hit the public NLB.
- In GitHub Actions, the runner IP is ephemeral and not predictable. The workflow therefore does **not** depend on public NLB access; it verifies via Kubernetes readiness (`kubectl rollout status`) only.
- Effective app allow-list is `default Wiz scanner CIDRs (from TF_VAR_dynamic_scanner_ipv4s_develop) + TF_VAR_allowed_cidrs`.
- If your tenant's scanner CIDRs differ from defaults, override `TF_VAR_dynamic_scanner_ipv4s_develop` and/or include those CIDRs in `TF_VAR_allowed_cidrs`.

## Workflow: `Demo Attack Simulation (Defend Telemetry)`

File: `.github/workflows/attack-sim.yml`

Triggered manually via `workflow_dispatch`. It:
1. Installs tooling via `mise`
2. Fetches the shared S3 backend config from SSM (assumes backend + environment are already deployed)
3. Reads Terraform outputs from the selected root (`infrastructure/demo` vs `infrastructure/demo-nowiz`)
4. Updates kubeconfig from the Terraform `cluster_name`
5. Runs `mise run attack-sim` using `kubectl port-forward` (runner-independent access) and the existing exploit chain script

Inputs:
- `enable_wiz`: selects which Terraform root to read state from (`demo` vs `demo-nowiz`)
- `backend_branch`: selects which SSM backend config parameter to read (defaults to `main`)

Notes:
- This workflow assumes the demo is already deployed (it does not run `deploy-demo` or `destroy-demo`).
- If you want to use CI to deploy and keep the environment up, run `demo-cycle` with `destroy=false` first.
- This is most useful when the environment was deployed with `enable_wiz=true` so the Wiz sensor/integration is present to generate Defend telemetry.

## Workflow: `Demo Banner Toggle (Visual Proof)`

File: `.github/workflows/attack-banner.yml`

Triggered manually via `workflow_dispatch`. It:
1. Resolves deployed Terraform state (same pattern as `attack-sim`)
2. Updates kubeconfig
3. Port-forwards to the live app service from the runner
4. Sets or resets `/tmp/banner.json` through `scripts/pwn-banner.sh`

Common usage:
- Set banner: `reset_banner=false`, provide `banner_message`
- Revert banner: `reset_banner=true`

### Required GitHub secrets (AWS)

The workflow expects these secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (optional, recommended)

These are used by the repo guardrail (`.mise-tasks/scripts/demo-aws.sh`) to:
- unset `AWS_PROFILE`
- force all calls to use the demo credentials
- refuse to run if AWS authentication fails for the provided access keys

### Required GitHub secrets (Wiz)

To apply Terraform resources that use the Wiz provider, set:
- `WIZ_CLIENT_ID`
- `WIZ_CLIENT_SECRET`

Important:
- Secrets do **not** transfer when creating a new repo from template.
- Each SE must set these in their own repo (or via org secrets with repo access).

### Optional GitHub secrets (Wiz CLI)

If you want `demo-cycle` to also run a Wiz Code scan from CI using `wizcli`, set:
- `WIZ_CLI_CLIENT_ID`
- `WIZ_CLI_CLIENT_SECRET`

If `skip_image=false`, the workflow will additionally:
- run `wizcli scan container-image` against the pushed ECR image tag `git-<sha12>`
- run `wizcli tag` (with the ECR image digest) to enable cloud-to-code mapping

Both steps are best-effort. This repo is intentionally vulnerable, so scans may fail by policy; the workflow still proceeds according to the selected `destroy` input.

### Terraform variable secrets for wiz-enabled demos

For full wiz-enabled demo behavior (`enable_wiz=true`), set:
- `TF_VAR_wiz_tenant_id`
- `TF_VAR_wiz_trusted_arn`
- `TF_VAR_wiz_client_environment`
- `TF_VAR_tenant_image_pull_username`
- `TF_VAR_tenant_image_pull_password`
- `TF_VAR_allowed_cidrs` (JSON list string, for example `["203.0.113.10/32"]`) to add operator and/or scanner CIDRs to app NetworkPolicy

`TF_VAR_dynamic_scanner_ipv4s_develop` is now baked into Terraform defaults for this demo and does not need to be set in GitHub secrets. You can still override it explicitly if your tenant uses a different scanner IP set.

If running `enable_wiz=false`, the Wiz-specific `TF_VAR_*` values above are not required.

## Future improvement (recommended): AWS OIDC

Access keys are fine for a throwaway account, but the preferred long-term setup is:
- GitHub OIDC + `aws-actions/configure-aws-credentials`
- A dedicated IAM role in the demo account with least-privilege permissions required for this demo
