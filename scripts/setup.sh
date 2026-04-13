#!/usr/bin/env bash
#
# setup.sh — Bootstrap the local development environment.
#
# Verifies the required toolchain is present and satisfies the minimum
# versions declared in package.json, then installs project dependencies
# with a deterministic `npm ci`.
#
# Usage:
#   ./scripts/setup.sh [--install-mode ci|install] [--skip-install] [-h|--help]
#
# Exit codes:
#   0  environment ready
#   1  missing prerequisites or install failure
#   2  invalid invocation
#
set -euo pipefail

INSTALL_MODE="ci"
SKIP_INSTALL=0

print_usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-mode) INSTALL_MODE="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    -h|--help)      print_usage; exit 0 ;;
    *)              echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

if [[ "${INSTALL_MODE}" != "ci" && "${INSTALL_MODE}" != "install" ]]; then
  echo "Invalid --install-mode: ${INSTALL_MODE} (expected 'ci' or 'install')" >&2
  exit 2
fi

# ---------- paths ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# ---------- ui ----------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_CYAN=""
fi

step()  { printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"; }
ok()    { printf '  %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
die()   { printf '  %s✗%s %s\n' "${C_RED}" "${C_RESET}" "$1"; exit 1; }

version_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]; }

# ---------- prerequisites ----------
step "Checking prerequisites"

command -v node >/dev/null 2>&1 || die "node is not installed"
command -v npm  >/dev/null 2>&1 || die "npm is not installed"
command -v git  >/dev/null 2>&1 || die "git is not installed"

NODE_VERSION="$(node -v | sed 's/^v//')"
REQUIRED_ENGINE="$(node -e "try { const p = require('./package.json'); process.stdout.write(p.engines?.node || ''); } catch {}")"
REQUIRED_MIN="$(echo "${REQUIRED_ENGINE}" | sed -E 's/^[^0-9]*//' | awk -F. '{print $1"."($2==""?"0":$2)"."($3==""?"0":$3)}')"

if [[ -z "${REQUIRED_MIN}" ]] || version_ge "${NODE_VERSION}" "${REQUIRED_MIN}"; then
  ok "node ${NODE_VERSION} (required ${REQUIRED_ENGINE:-any})"
else
  die "node ${NODE_VERSION} does not satisfy engines.node ${REQUIRED_ENGINE}"
fi

ok "npm $(npm -v)"
ok "git $(git --version | awk '{print $3}')"

# ---------- install ----------
if [[ ${SKIP_INSTALL} -eq 1 ]]; then
  step "Skipping dependency install (--skip-install)"
else
  step "Installing dependencies (npm ${INSTALL_MODE})"
  if [[ "${INSTALL_MODE}" == "ci" && ! -f package-lock.json ]]; then
    echo "  package-lock.json missing — falling back to 'npm install'"
    INSTALL_MODE="install"
  fi
  npm "${INSTALL_MODE}"
  ok "dependencies installed"
fi

# ---------- done ----------
printf '\n%s%s✓ environment ready%s\n' "${C_BOLD}" "${C_GREEN}" "${C_RESET}"
printf '  Next: %snpm start%s or %s./scripts/ci-local.sh%s\n' "${C_BOLD}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"
