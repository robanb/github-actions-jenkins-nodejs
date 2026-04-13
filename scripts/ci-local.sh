#!/usr/bin/env bash
#
# ci-local.sh — Run the exact same steps the GitHub Actions pipeline
# runs, locally. Use this before pushing to catch red builds early.
#
# Steps:
#   1. npm ci                  (deterministic install)
#   2. npm run lint            (ESLint)
#   3. npm run test:coverage   (Jest with coverage gate)
#
# Usage:
#   ./scripts/ci-local.sh [--skip-install] [-h|--help]
#
# Exit codes:
#   0  all steps succeeded
#   1  any step failed
#   2  invalid invocation
#
set -euo pipefail

SKIP_INSTALL=0

print_usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help)      print_usage; exit 0 ;;
    *)              echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_CYAN=""
fi

step() { printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"; }

START_TS=$(date +%s)

run_step() {
  local label="$1"; shift
  step "${label}"
  if "$@"; then
    printf '  %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    printf '\n%s%s✗ step failed:%s %s\n' "${C_BOLD}" "${C_RED}" "${C_RESET}" "${label}"
    exit 1
  fi
}

printf '%s%s sample-node-ci :: local CI %s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"

if [[ ${SKIP_INSTALL} -eq 0 ]]; then
  run_step "Install dependencies (npm ci)" npm ci
else
  step "Skipping dependency install (--skip-install)"
fi

run_step "Lint (npm run lint)"                  npm run lint
run_step "Test + coverage (npm run test:coverage)" npm run test:coverage

END_TS=$(date +%s)
printf '\n%s%s✓ local CI passed in %ds%s\n' "${C_BOLD}" "${C_GREEN}" "$((END_TS - START_TS))" "${C_RESET}"
