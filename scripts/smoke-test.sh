#!/usr/bin/env bash
#
# smoke-test.sh — End-to-end smoke test against a running nodejs-ci-demo.
#
# Exercises each public endpoint and verifies HTTP status, content type,
# and a key field in the JSON body. Intended to be run post-deploy or
# after `npm start` to confirm the service is behaving correctly.
#
# Usage:
#   ./scripts/smoke-test.sh [--url <base-url>] [--timeout <seconds>] [-h|--help]
#
# Exit codes:
#   0  all smoke tests passed
#   1  one or more tests failed
#   2  invalid invocation
#
set -euo pipefail

BASE_URL="${SMOKE_URL:-http://localhost:3000}"
TIMEOUT=5

print_usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)      BASE_URL="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    -h|--help)  print_usage; exit 0 ;;
    *)          echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_CYAN=""
fi

PASSED=0
FAILED=0

BASE_URL="${BASE_URL%/}"
printf '%s%s nodejs-ci-demo :: smoke test %s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"
printf '%starget:%s %s\n\n' "${C_DIM}" "${C_RESET}" "${BASE_URL}"

# Run one assertion.
# $1: descriptive name
# $2: HTTP path (e.g. /health)
# $3: expected HTTP status
# $4: substring that must appear in the JSON body
assert() {
  local name="$1" path="$2" want_status="$3" want_body="$4"
  local tmp http_code body

  tmp="$(mktemp)"
  http_code="$(curl -sS -o "${tmp}" -w '%{http_code}' --max-time "${TIMEOUT}" "${BASE_URL}${path}" 2>/dev/null || echo '000')"
  body="$(cat "${tmp}")"
  rm -f "${tmp}"

  if [[ "${http_code}" == "${want_status}" ]] && printf '%s' "${body}" | grep -q -- "${want_body}"; then
    printf '  %s✓%s %s %s(%s)%s\n' "${C_GREEN}" "${C_RESET}" "${name}" "${C_DIM}" "${http_code}" "${C_RESET}"
    PASSED=$((PASSED + 1))
  else
    printf '  %s✗%s %s %s(got %s, want %s)%s\n' "${C_RED}" "${C_RESET}" "${name}" "${C_DIM}" "${http_code}" "${want_status}" "${C_RESET}"
    printf '    %sbody:%s %s\n' "${C_DIM}" "${C_RESET}" "${body}"
    FAILED=$((FAILED + 1))
  fi
}

assert "GET /"                        "/"                 "200" '"Hello, CI/CD!"'
assert "GET /health"                  "/health"           "200" '"status":"ok"'
assert "GET /sum (2+3)"               "/sum?a=2&b=3"      "200" '"result":5'
assert "GET /sum (negatives)"         "/sum?a=-4&b=10"    "200" '"result":6'
assert "GET /sum (invalid inputs)"    "/sum?a=foo&b=3"    "400" '"status":400'
assert "GET /sum (missing params)"    "/sum"              "400" '"status":400'
assert "GET /does-not-exist (404)"    "/does-not-exist"   "404" '"status":404'

printf '\n'
if [[ ${FAILED} -eq 0 ]]; then
  printf '%s%s✓ %d smoke test(s) passed%s\n' "${C_BOLD}" "${C_GREEN}" "${PASSED}" "${C_RESET}"
  exit 0
else
  printf '%s%s✗ %d passed, %d failed%s\n' "${C_BOLD}" "${C_RED}" "${PASSED}" "${FAILED}" "${C_RESET}"
  exit 1
fi
