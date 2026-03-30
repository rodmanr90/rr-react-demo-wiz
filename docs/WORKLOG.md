# Worklog

Last updated: 2026-02-17

## Context

This repository (`wiz-react-e2e-demo`) was created as a clean, repeatable Wiz demo repo (Wiz Code + Cloud + Defend).

It was initialized by copying a curated subset of content from:

- `/Users/lucasjarman/Code/wiz-master-demo`

The intent is to iterate here going forward (and stop changing the source repo).

## Initial Import Snapshot (2026-02-06)

Copied from the source repo with these exclusions:

- no `.git/` history (fresh repo)
- no `kubeconfig*`
- no `fnox.toml` or `mise.local.toml`
- no generated `infrastructure/backend-config.json`
- no terraform `.terraform/` directories, lockfiles, or state artifacts

## Key Decisions

- Prefer a **single-root Terraform module**: `infrastructure/demo/`.
- Avoid ArgoCD owning K8s resources. K8s integrations should be Terraform-owned for deterministic destroy.
- CI should be able to run a full `deploy -> destroy` cycle while retaining a stable S3 backend so Wiz can ingest Terraform state for code-to-cloud mapping.

## 2026-02-06 Updates

- Removed ArgoCD from `modules/k8s-services` and deploy Wiz K8s integration directly via Terraform `helm_release` (pinned `wiz-kubernetes-integration` chart version `0.3.13`).
- Hardened AWS guardrails: `deploy-demo`/`destroy-demo`/`bootstrap-branch`/`build-image` now require explicit `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars and print `aws sts get-caller-identity` for operator visibility (no account-id matching).
- Fixed Wiz Helm chart environment configuration: `TF_VAR_wiz_client_environment` now defaults to `prod` (previously set to an invalid value like `app.wiz.io`).
- Simplified workflow surface area: removed legacy GitHub Actions workflows; only `ci` and `demo-cycle` remain.
- Backend lifecycle: `destroy-demo` keeps the backend by default for fast local iteration. Use `--destroy-backend` only when you intentionally want to tear down the state bucket (this will break Wiz code-to-cloud mapping until recreated).
- Wiz code-to-cloud mapping: switched `demo-cycle` to reuse a stable S3 backend (do not destroy backend bucket by default) so Wiz can ingest Terraform state for mapping.
- Wiz code-to-cloud mapping: made the backend bucket name deterministic (includes AWS account id + region) so committed `iac_config.wiz` remains valid even if you destroy/recreate the backend in the same account/region.
- Added Wiz CLI to `demo-cycle` (optional) to run:
  - directory scans (`wizcli scan dir .`) for Wiz Code findings
  - container image scans + tagging (`wizcli scan container-image` + `wizcli tag`) to enable cloud-to-code mapping for the pushed ECR image digest
- Fixed `build-image` to read the ECR repository URL from Terraform outputs and push additional traceability tags (e.g. `git-<sha>`).
- Improved `build-image` reliability on Apple Silicon by preferring `docker buildx build --platform linux/amd64 --load` when `buildx` is available.
- Destroy reliability fixes:
  - `pre-destroy-cleanup` now waits for ELB/NLB ENIs to be released (in addition to deleting the load balancer), preventing subnet deletion `DependencyViolation` hangs.
  - `pre-destroy-cleanup` best-effort revokes security group rules in other SGs that reference `k8s-*` SGs before deleting them (prevents `DependencyViolation` on SG delete).
  - `destroy-demo` runs `terraform init` before reading outputs so it reliably finds `vpc_id` and runs pre-cleanup.
  - `destroy-demo --destroy-backend` is now skipped if the demo destroy fails (keeps state for recovery instead of orphaning resources).
  - `destroy-demo` backend migration no longer uses mutually exclusive `terraform init` flags.

## 2026-02-07 Updates

- Fixed `demo-cycle` destroy failure caused by missing `rg` on GitHub runners:
  - `.mise-tasks/destroy-demo` no longer depends on `rg` (uses `grep`).
- Made `destroy-demo` resilient to partial-destroy state edge cases:
  - If Terraform state has no outputs (can happen after a partially-failed destroy), `destroy-demo` falls back to reading `cluster_name` / `vpc_id` from `terraform state show`.
  - If Terraform state cannot be read (e.g. lock issues), `destroy-demo` falls back to selecting a VPC by AWS tags (only when exactly 1 match exists).
  - Fixed state-lock auto-unlock parsing to handle logs that include prefixed characters (e.g. box-drawing output).
- Improved teardown reliability by ensuring `kubectl` can be invoked in CI:
  - `.mise-tasks/scripts/pre-destroy-cleanup` now uses `kubectl` if present, otherwise `mise exec -- kubectl`.

## 2026-02-08 Updates

- Removed unused `iac_config.wiz` generator/template:
  - Deleted `.mise-tasks/create-wiz-iac-files`
  - Deleted `templates/iac_config.wiz.template`
  - `iac_config.wiz` files are now treated as repo-managed, stable config (bucket name is deterministic per account/region).
- Improved `deploy-demo` resilience when Wiz is enabled:
  - `.mise-tasks/deploy-demo` retries `terraform apply` up to 3 times when failures match transient Wiz API/network errors.
- Made Wiz container tagging in CI best-effort:
  - `.github/workflows/demo-cycle.yml` now retries ECR digest lookup and does not fail the run if `wizcli tag` fails.
- Demo-cycle validation runs completed successfully on `chore/simplify-repo`:
  - `21788281066` (enable_wiz=false)
  - `21788698601` (enable_wiz=true)
- Demo-cycle validation run completed successfully on `main`:
  - `21791489155` (enable_wiz=false)

## 2026-02-09 Updates

- Split attack simulation out of `demo-cycle` to keep it boring and repeatable:
  - Added `.github/workflows/attack-sim.yml` (assumes the demo is already deployed; no deploy/destroy)
  - `attack-sim` fetches backend config from SSM, reads Terraform outputs, updates kubeconfig, then runs `mise run attack-sim`
- Added `mise run attack-sim` task for a deterministic, runner-independent exploit chain:
  - Uses `kubectl port-forward` + `scripts/exploit/wiz-demo-v4.sh`
  - Drops `/tmp/banner.json` in the workload for a quick visual compromise check

## 2026-02-11 Updates

- Fixed exploit payload generation regression in `scripts/exploit/wiz-demo-v4.sh`:
  - Command is now passed to python via stdin while python source is provided via a separate FD (avoids putting reverse-shell strings in `python3` argv).
  - Removed `\\$` escaping in the payload template so the multipart content matches the original working payload.
  - `rce()` now retries and fails fast if the HTTP request cannot connect (stops silently “passing” when port-forward is flaky).
- Made `attack-sim` verification deterministic:
  - Clears `/tmp/banner.json` before running the exploit chain.
  - Checks all matching pods for the banner file (avoids false negatives if the service briefly targets an old pod during rollout).
- Hardened `iac_config.wiz` backend definitions for Wiz IaC code-to-cloud mapping:
  - Updated `infrastructure/backends/iac_config.wiz`
  - Updated `infrastructure/demo/iac_config.wiz`
  - Updated `infrastructure/demo-nowiz/iac_config.wiz`
  - Each dynamic backend now explicitly includes all S3 backend attributes used by this repo:
    - `bucket`
    - `key`
    - `region`
    - `encrypt`
    - `use_lockfile`
- Updated committed Terraform backend blocks to explicitly include required S3 backend attributes:
  - `infrastructure/backends/backend.tf`
  - `infrastructure/demo/backend.tf`
  - `infrastructure/demo-nowiz/backend.tf`
  - Added explicit `bucket`, `key`, `region`, `encrypt`, and `use_lockfile`
- Validated a clean no-wiz demo loop locally (deploy -> attack-sim -> destroy) with Wiz connector creation still disabled:
  - `mise run deploy-demo --no-wiz --skip-verify`
  - `mise run attack-sim --no-wiz`
  - `mise run destroy-demo --no-dry-run --no-wiz`

## 2026-02-12 Updates

- Made Terraform backend generation durable for Wiz mapping portability:
  - Updated `.mise-tasks/init-backends` to always generate `backend.tf` with explicit S3 attributes:
    - `bucket`
    - `key`
    - `region`
    - `encrypt`
    - `use_lockfile`
  - Added a completeness check in `.mise-tasks/init-backends` so existing partial `backend.tf` files are automatically rewritten.
  - Updated `.mise-tasks/bootstrap-branch` (both existing-backend and new-backend paths) to generate `infrastructure/backends/backend.tf` with explicit `bucket`, `key`, `region`, `encrypt`, and `use_lockfile`.
- Validation notes:
  - Full `mise run init-backends` requires AWS credentials (fails without them at `terraform init`).
  - Verified generation behavior with a mocked `terraform` binary and confirmed resulting files include all required backend attributes:
    - `infrastructure/backends/backend.tf`
    - `infrastructure/demo/backend.tf`
    - `infrastructure/demo-nowiz/backend.tf`

## 2026-02-15 Updates

- IaC code-to-cloud mapping (Wiz) hardening:
  - Added an explicit, narrow IAM policy attachment in `infrastructure/demo/main.tf` granting the Wiz role read access to this repo's deterministic Terraform state backend bucket/key paths.
  - Rationale: Wiz's standard Terraform scanning policy scopes S3 access by bucket-name patterns (e.g. `*tfstate*` / `*terraform*`), but this repo's deterministic backend bucket name (`demo-...-state-bucket-...`) may not match those patterns, breaking mapping unless explicitly permitted.

## 2026-02-16 Updates

- CI Wiz-enabled `demo-cycle` failure fix (new AWS accounts):
  - Observed `CREATE_FAILED` for EKS managed nodegroup with `AccessDenied: ... unable to assume the service-linked role in your account`.
  - Mitigation: `.mise-tasks/deploy-demo` now proactively ensures the required EKS service-linked roles exist:
    - `AWSServiceRoleForAmazonEKS` (`eks.amazonaws.com`)
    - `AWSServiceRoleForAmazonEKSNodegroup` (`eks-nodegroup.amazonaws.com`)
  - This makes the repo more portable across fresh AWS accounts where the service-linked roles may not exist yet (or cannot be auto-created).

## 2026-02-17 Updates

- Added deterministic deployment naming support across both Terraform roots:
  - New `deployment_name` input variable in:
    - `infrastructure/demo/variables.tf`
    - `infrastructure/demo-nowiz/variables.tf`
  - Naming local now uses:
    - provided `deployment_name` when set
    - fallback random suffix for backwards compatibility
  - Added canonical `deployment_name` output in:
    - `infrastructure/demo/outputs.tf`
    - `infrastructure/demo-nowiz/outputs.tf`
- Updated deploy/destroy tasks to use one consistent deployment identifier:
  - `.mise-tasks/deploy-demo`:
    - new `--deployment-name` flag
    - auto-generates a deployment name if not provided
    - reuses existing state deployment name when available
    - exports `TF_VAR_deployment_name` before `terraform apply`
  - `.mise-tasks/destroy-demo`:
    - now prints detected deployment name from Terraform outputs for operator clarity
- Updated GitHub workflows for repeatable, click-button runs:
  - `.github/workflows/demo-cycle.yml`:
    - new `deployment_name` input
    - always sets `TF_VAR_deployment_name` (input value or `run-<id>-<attempt>` default)
    - summary now includes both `deployment_name` and `suffix`
  - `.github/workflows/attack-sim.yml`:
    - reads service/deployment directly from Terraform outputs (instead of reconstructing names)
    - prints resolved deployment identifier in logs
- Updated `AGENTS.md` with reset-safe operational instructions:
  - deployment naming invariant
  - backend/IaC mapping invariant (explicit backend attributes)
  - GitHub-first runbook and isolated attack-sim expectations
  - fresh AWS account validation steps
- Fixed auto-generated deployment name length for EKS IAM compatibility:
  - Observed failure when auto-generated name exceeded AWS IAM `name_prefix` constraints in the EKS module.
  - Tightened `deployment_name` max length to 16 chars in Terraform variable validation.
  - Updated CI default generator to `r<run_id>-<attempt>` so it always stays within limits.
  - Hardened `.mise-tasks/deploy-demo` existing-state name detection by parsing `terraform output -json` (avoids warning text being treated as a name).
- Made canonical backend files visible in Git for IaC mapping transparency:
  - Updated `.gitignore` to track:
    - `infrastructure/backends/backend.tf`
    - `infrastructure/demo/backend.tf`
    - `infrastructure/demo-nowiz/backend.tf`
  - Committed explicit backend blocks (bucket/key/region/encrypt/use_lockfile) for the active demo account.
- Added automatic backend drift sync in CI to keep VCS and runtime backend metadata aligned:
  - Added `.mise-tasks/sync-backend-files` to render canonical backend files from `infrastructure/backend-config.json`.
  - Updated `demo-cycle` to:
    - run backend sync after bootstrap
    - auto-commit/push drift in:
      - `infrastructure/backend-config.json`
      - `infrastructure/backends/backend.tf`
      - `infrastructure/demo/backend.tf`
      - `infrastructure/demo-nowiz/backend.tf`
  - Updated workflow permissions to `contents: write` for this sync commit.
  - Rationale: avoid VCS/backend mismatch that can break IaC code-to-cloud mapping in cross-account demo runs.
  - Follow-up CI fix: `demo-cycle` now calls `bootstrap-branch --force` because `infrastructure/backend-config.json` is tracked; without `--force`, bootstrap aborted on existing config.

## Next Goals

- Make this repo a portable, repeatable demo bootstrap for Wiz SEs:
  - documented prerequisites, secrets, and minimal operator steps
  - predictable demo lifecycle that is boring: `deploy -> verify -> destroy`
- Simplify the codebase for repeatability:
  - remove unused modules/files/scripts
  - reduce conditional logic and hidden coupling between tasks
  - keep CI and local flows aligned (same tasks, same Terraform roots)
- Improve the CI "attack simulation" path for Wiz Defend telemetry (currently `attack-sim` workflow + `mise run attack-sim`):
  - consider a purpose-built in-cluster "attacker" pod (more realistic, avoids port-forward)
  - keep it opt-in and deterministic (no external callbacks required)
