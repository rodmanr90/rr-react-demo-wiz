#!/usr/bin/env bash
#
# Lightweight wrapper for banner-only exploit mode.
# Uses scripts/exploit/wiz-demo-v4.sh to set/reset /tmp/banner.json only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WIZ_DEMO_SCRIPT="${SCRIPT_DIR}/exploit/wiz-demo-v4.sh"

TF_DIR_REL="infrastructure/demo"
NLB_HOST=""
RESET_MODE="false"
MESSAGE="COMPROMISED"

usage() {
  cat <<'USAGE'
Usage: scripts/pwn-banner.sh [nlb-hostname] [options]

Options:
  -r, --reset           Remove /tmp/banner.json
  -m, --message <msg>   Banner message (default: COMPROMISED)
      --no-wiz          Use infrastructure/demo-nowiz for host auto-detection
  -h, --help            Show this help

Examples:
  scripts/pwn-banner.sh k8s-abc.elb.amazonaws.com
  scripts/pwn-banner.sh --message "PWNED"
  scripts/pwn-banner.sh --reset
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--reset)
      RESET_MODE="true"
      shift
      ;;
    -m|--message)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --message requires a value" >&2
        exit 1
      fi
      MESSAGE="$2"
      shift 2
      ;;
    --no-wiz)
      TF_DIR_REL="infrastructure/demo-nowiz"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "${NLB_HOST}" ]]; then
        echo "ERROR: multiple hostnames provided: ${NLB_HOST}, $1" >&2
        exit 1
      fi
      NLB_HOST="$1"
      shift
      ;;
  esac
done

if [[ ! -x "${WIZ_DEMO_SCRIPT}" ]]; then
  echo "ERROR: missing executable helper script: ${WIZ_DEMO_SCRIPT}" >&2
  exit 1
fi

autodetect_nlb() {
  local tf_dir="${REPO_ROOT}/${TF_DIR_REL}"
  local ns=""
  local svc=""
  local host=""

  if command -v terraform >/dev/null 2>&1 && command -v kubectl >/dev/null 2>&1 && [[ -d "${tf_dir}" ]]; then
    terraform -chdir="${tf_dir}" init -input=false >/dev/null 2>&1 || true
    ns="$(terraform -chdir="${tf_dir}" output -raw react2shell_namespace 2>/dev/null || true)"
    svc="$(terraform -chdir="${tf_dir}" output -raw react2shell_service_name 2>/dev/null || true)"

    if [[ -n "${ns}" && -n "${svc}" && "${ns}" != "null" && "${svc}" != "null" ]]; then
      host="$(kubectl -n "${ns}" get svc "${svc}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi
  fi

  if [[ -n "${host}" ]]; then
    printf '%s\n' "${host}"
    return 0
  fi
  return 1
}

if [[ -z "${NLB_HOST}" ]]; then
  if ! NLB_HOST="$(autodetect_nlb)"; then
    echo "ERROR: could not auto-detect NLB hostname." >&2
    echo "Provide it explicitly: scripts/pwn-banner.sh <nlb-hostname>" >&2
    exit 1
  fi
fi

if [[ "${RESET_MODE}" == "true" ]]; then
  exec "${WIZ_DEMO_SCRIPT}" "${NLB_HOST}" --reset-banner
fi

exec "${WIZ_DEMO_SCRIPT}" "${NLB_HOST}" --banner-only --banner-message "${MESSAGE}"
