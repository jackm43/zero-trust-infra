#!/usr/bin/env bash
set -euo pipefail

# Deploys infra/ then vault-config/ with secrets pulled from 1Password at
# runtime via `op run`, instead of a plaintext .env file.
#
# Usage:
#   scripts/deploy.sh plan              # plan both stacks
#   scripts/deploy.sh apply             # apply both stacks
#   scripts/deploy.sh apply infra       # apply just infra/
#   scripts/deploy.sh apply vault-config # apply just vault-config/
#
# Requires: 1Password CLI (`op`) signed in, and op.env filled in with your
# vault/item/field references (see op.env in the repo root).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/op.env"

ACTION="${1:-plan}"
TARGET="${2:-all}"

if [[ "${ACTION}" != "plan" && "${ACTION}" != "apply" ]]; then
  echo "Usage: $0 <plan|apply> [infra|vault-config|all]" >&2
  exit 1
fi

if ! command -v op >/dev/null 2>&1; then
  echo "1Password CLI ('op') not found. Install it: https://developer.1password.com/docs/cli/get-started/" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE} - copy the op:// references template and point it at your vault items." >&2
  exit 1
fi

if ! op whoami >/dev/null 2>&1; then
  echo "Not signed in to 1Password CLI. Run 'op signin' first." >&2
  exit 1
fi

run_stack() {
  local stack_dir="$1"
  echo "==> ${ACTION} in ${stack_dir}"
  (
    cd "${ROOT_DIR}/${stack_dir}"
    op run --env-file="${ENV_FILE}" -- terraform init -input=false
    op run --env-file="${ENV_FILE}" -- terraform "${ACTION}" ${ACTION_FLAGS:-}
  )
}

case "${ACTION}" in
  apply) ACTION_FLAGS="-auto-approve" ;;
  *) ACTION_FLAGS="" ;;
esac

case "${TARGET}" in
  infra) run_stack "infra" ;;
  vault-config) run_stack "vault-config" ;;
  all)
    run_stack "infra"
    run_stack "vault-config"
    ;;
  *)
    echo "Unknown target '${TARGET}'. Use infra, vault-config, or all." >&2
    exit 1
    ;;
esac
