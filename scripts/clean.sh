#!/usr/bin/env bash
#
# clean.sh — Remove generated artifacts from the working tree.
#
# Clears node_modules, coverage reports, Jest cache, and common editor
# droppings so you can start from a known-clean state (or prepare a tidy
# archive for submission).
#
# Usage:
#   ./scripts/clean.sh [--deep] [--dry-run] [-h|--help]
#
# Options:
#   --deep     also remove package-lock.json and .eslintcache
#   --dry-run  print what would be removed without deleting
#
# Exit codes:
#   0  cleanup completed
#   2  invalid invocation
#
set -euo pipefail

DEEP=0
DRY_RUN=0

print_usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deep)    DEEP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *)         echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi

TARGETS=(
  "node_modules"
  "coverage"
  ".jest-cache"
  ".eslintcache"
  "npm-debug.log"
)

if [[ ${DEEP} -eq 1 ]]; then
  TARGETS+=("package-lock.json")
fi

printf '%s%s nodejs-ci-demo :: clean %s\n' "${C_BOLD}" "${C_CYAN}" "${C_RESET}"
printf '%sroot:%s %s\n' "${C_DIM}" "${C_RESET}" "${PROJECT_ROOT}"
[[ ${DRY_RUN} -eq 1 ]] && printf '%s(dry run — no files will be removed)%s\n' "${C_YELLOW}" "${C_RESET}"
printf '\n'

REMOVED=0
for target in "${TARGETS[@]}"; do
  if [[ -e "${target}" ]]; then
    if [[ ${DRY_RUN} -eq 1 ]]; then
      printf '  would remove %s%s%s\n' "${C_BOLD}" "${target}" "${C_RESET}"
    else
      rm -rf -- "${target}"
      printf '  %s✓%s removed %s\n' "${C_GREEN}" "${C_RESET}" "${target}"
    fi
    REMOVED=$((REMOVED + 1))
  fi
done

printf '\n'
if [[ ${REMOVED} -eq 0 ]]; then
  printf '%s%s✓ already clean%s\n' "${C_BOLD}" "${C_GREEN}" "${C_RESET}"
else
  printf '%s%s✓ cleaned %d item(s)%s\n' "${C_BOLD}" "${C_GREEN}" "${REMOVED}" "${C_RESET}"
fi
