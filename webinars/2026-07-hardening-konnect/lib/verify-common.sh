# Shared helpers for lab verify.sh scripts: colored PASS/FAIL/WARN lines
# plus a final summary table. Source this file, call check_* as tests run,
# then call verify_summary at the end (it exits non-zero on any failure).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/verify-common.sh"
#   check_pass "Team exists in Konnect"
#   check_fail "Developer DELETE blocked with 403" "expected 403, got 200"
#   check_warn "No audit log entries found"
#   verify_summary "Lab 3"

_VERIFY_NAMES=()
_VERIFY_RESULTS=()

if [[ -t 1 ]]; then
  _C_GREEN=$'\033[32m'; _C_RED=$'\033[31m'; _C_YELLOW=$'\033[33m'; _C_BOLD=$'\033[1m'; _C_RESET=$'\033[0m'
else
  _C_GREEN=""; _C_RED=""; _C_YELLOW=""; _C_BOLD=""; _C_RESET=""
fi

check_pass() {
  local name="$1"
  echo "  ${_C_GREEN}PASS${_C_RESET}  $name"
  _VERIFY_NAMES+=("$name")
  _VERIFY_RESULTS+=("PASS")
}

check_fail() {
  local name="$1" detail="${2:-}"
  if [[ -n "$detail" ]]; then
    echo "  ${_C_RED}FAIL${_C_RESET}  $name — $detail"
  else
    echo "  ${_C_RED}FAIL${_C_RESET}  $name"
  fi
  _VERIFY_NAMES+=("$name")
  _VERIFY_RESULTS+=("FAIL")
}

check_warn() {
  local name="$1" detail="${2:-}"
  if [[ -n "$detail" ]]; then
    echo "  ${_C_YELLOW}WARN${_C_RESET}  $name — $detail"
  else
    echo "  ${_C_YELLOW}WARN${_C_RESET}  $name"
  fi
  _VERIFY_NAMES+=("$name")
  _VERIFY_RESULTS+=("WARN")
}

# Prints the pass/fail/warn summary table and exits non-zero if any check failed.
verify_summary() {
  local title="${1:-Verification}"
  local total=${#_VERIFY_NAMES[@]}
  local pass_count=0 fail_count=0 warn_count=0
  local i

  echo ""
  echo "${_C_BOLD}==> $title summary${_C_RESET}"
  for ((i = 0; i < total; i++)); do
    local result="${_VERIFY_RESULTS[$i]}" name="${_VERIFY_NAMES[$i]}"
    case "$result" in
      PASS) echo "  ${_C_GREEN}✓${_C_RESET} $name"; ((pass_count++)) ;;
      FAIL) echo "  ${_C_RED}✗${_C_RESET} $name"; ((fail_count++)) ;;
      WARN) echo "  ${_C_YELLOW}!${_C_RESET} $name"; ((warn_count++)) ;;
    esac
  done

  echo ""
  echo "  ${pass_count}/${total} passed, ${fail_count} failed, ${warn_count} warned"

  if ((fail_count > 0)); then
    echo "  ${_C_RED}${_C_BOLD}RESULT: FAIL${_C_RESET}"
    exit 1
  else
    echo "  ${_C_GREEN}${_C_BOLD}RESULT: PASS${_C_RESET}"
  fi
}
