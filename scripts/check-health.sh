#!/usr/bin/env bash
#
# check-health.sh — System and service health inspection for sample-node-ci.
#
# Collects host specs, verifies Node.js / npm meet the project's minimum
# versions (as declared in package.json `engines.node`), and probes the
# running server's /health endpoint.
#
# Usage:
#   ./scripts/check-health.sh [--url <base-url>] [--timeout <seconds>] [--no-color] [-h|--help]
#
# Exit codes:
#   0  all checks passed
#   1  one or more checks failed
#   2  invalid invocation
#
set -euo pipefail

# ---------- defaults ----------
BASE_URL="${HEALTH_URL:-http://localhost:3000}"
TIMEOUT=5
USE_COLOR=1

# ---------- argument parsing ----------
print_usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)       BASE_URL="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    --no-color)  USE_COLOR=0; shift ;;
    -h|--help)   print_usage; exit 0 ;;
    *)           echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

# ---------- colors ----------
if [[ $USE_COLOR -eq 1 && -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

FAILED=0

section() {
  printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
}

kv() {
  printf '  %-22s %s\n' "$1" "$2"
}

pass() {
  printf '  %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}

warn() {
  printf '  %s!%s %s\n' "${C_YELLOW}" "${C_RESET}" "$1"
}

fail() {
  printf '  %s✗%s %s\n' "${C_RED}" "${C_RESET}" "$1"
  FAILED=$((FAILED + 1))
}

# ---------- resolve project root ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_JSON="${PROJECT_ROOT}/package.json"

# ---------- helpers ----------
# Extract a field from package.json without requiring jq.
pkg_field() {
  local key="$1"
  node -e "try { const p = require('${PKG_JSON}'); const k = '${key}'.split('.'); let v = p; for (const s of k) v = v?.[s]; process.stdout.write(v ?? ''); } catch { process.exit(0); }" 2>/dev/null || true
}

# Compare two dotted version strings. Returns 0 iff $1 >= $2.
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]
}

# ---------- banner ----------
printf '%s%s sample-node-ci :: health check %s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"
printf '%sroot:%s %s\n' "${C_DIM}" "${C_RESET}" "${PROJECT_ROOT}"
printf '%starget:%s %s\n' "${C_DIM}" "${C_RESET}" "${BASE_URL}"

# ---------- 1. host specs ----------
section "Host"
kv "Hostname"     "$(hostname)"
kv "User"         "$(id -un)"
kv "OS"           "$(uname -srmo 2>/dev/null || uname -a)"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  kv "Distribution" "${PRETTY_NAME:-${NAME:-unknown}}"
fi

if command -v nproc >/dev/null 2>&1; then
  kv "CPU cores"  "$(nproc)"
elif command -v sysctl >/dev/null 2>&1; then
  kv "CPU cores"  "$(sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
fi

if command -v free >/dev/null 2>&1; then
  kv "Memory"     "$(free -h | awk '/^Mem:/ {printf "%s used / %s total", $3, $2}')"
fi

if command -v df >/dev/null 2>&1; then
  kv "Disk (root)" "$(df -h / | awk 'NR==2 {printf "%s used / %s total (%s free)", $3, $2, $4}')"
fi

if command -v uptime >/dev/null 2>&1; then
  kv "Uptime"     "$(uptime -p 2>/dev/null || uptime)"
fi

# ---------- 2. toolchain ----------
section "Toolchain"

if command -v node >/dev/null 2>&1; then
  NODE_VERSION="$(node -v | sed 's/^v//')"
  kv "node"       "v${NODE_VERSION}"

  REQUIRED_ENGINE="$(pkg_field 'engines.node')"
  if [[ -n "${REQUIRED_ENGINE}" ]]; then
    REQUIRED_MIN="$(echo "${REQUIRED_ENGINE}" | sed -E 's/^[^0-9]*//' | awk -F. '{print $1"."($2==""?"0":$2)"."($3==""?"0":$3)}')"
    if version_ge "${NODE_VERSION}" "${REQUIRED_MIN}"; then
      pass "node ${NODE_VERSION} satisfies engines.node ${REQUIRED_ENGINE}"
    else
      fail "node ${NODE_VERSION} does NOT satisfy engines.node ${REQUIRED_ENGINE}"
    fi
  else
    warn "package.json does not declare engines.node"
  fi
else
  fail "node is not installed or not on PATH"
fi

if command -v npm >/dev/null 2>&1; then
  kv "npm"        "$(npm -v)"
else
  fail "npm is not installed or not on PATH"
fi

if [[ -r "${PROJECT_ROOT}/.nvmrc" ]]; then
  kv ".nvmrc pin"  "$(tr -d '[:space:]' < "${PROJECT_ROOT}/.nvmrc")"
fi

if command -v git >/dev/null 2>&1; then
  kv "git"        "$(git --version | awk '{print $3}')"
fi

if command -v curl >/dev/null 2>&1; then
  kv "curl"       "$(curl --version | awk 'NR==1{print $2}')"
else
  fail "curl is required for the HTTP probe but is not installed"
fi

# ---------- 3. project state ----------
section "Project"

if [[ -f "${PKG_JSON}" ]]; then
  kv "name"       "$(pkg_field 'name')"
  kv "version"    "$(pkg_field 'version')"
  pass "package.json present"
else
  fail "package.json not found at ${PKG_JSON}"
fi

if [[ -d "${PROJECT_ROOT}/node_modules" ]]; then
  pass "node_modules installed"
else
  warn "node_modules missing — run 'npm ci'"
fi

if [[ -f "${PROJECT_ROOT}/package-lock.json" ]]; then
  pass "package-lock.json present"
else
  warn "package-lock.json missing — CI's 'npm ci' will fail"
fi

# ---------- 4. service probe ----------
section "Service"

if ! command -v curl >/dev/null 2>&1; then
  fail "skipping service probe (curl not available)"
else
  HEALTH_URL="${BASE_URL%/}/health"
  kv "Probing"    "${HEALTH_URL}"

  HTTP_RESPONSE_FILE="$(mktemp)"
  trap 'rm -f "${HTTP_RESPONSE_FILE}"' EXIT

  if HTTP_CODE="$(curl -sS -o "${HTTP_RESPONSE_FILE}" -w '%{http_code}' --max-time "${TIMEOUT}" "${HEALTH_URL}" 2>/dev/null)"; then
    BODY="$(cat "${HTTP_RESPONSE_FILE}")"
    if [[ "${HTTP_CODE}" == "200" ]]; then
      pass "GET ${HEALTH_URL} → ${HTTP_CODE}"
      printf '%s      body:%s %s\n' "${C_DIM}" "${C_RESET}" "${BODY}"
    else
      fail "GET ${HEALTH_URL} → ${HTTP_CODE}"
      [[ -n "${BODY}" ]] && printf '%s      body:%s %s\n' "${C_DIM}" "${C_RESET}" "${BODY}"
    fi
  else
    fail "cannot reach ${HEALTH_URL} (server not running? timeout=${TIMEOUT}s)"
  fi
fi

# ---------- summary ----------
printf '\n'
if [[ ${FAILED} -eq 0 ]]; then
  printf '%s%s✓ all checks passed%s\n' "${C_BOLD}" "${C_GREEN}" "${C_RESET}"
  exit 0
else
  printf '%s%s✗ %d check(s) failed%s\n' "${C_BOLD}" "${C_RED}" "${FAILED}" "${C_RESET}"
  exit 1
fi
