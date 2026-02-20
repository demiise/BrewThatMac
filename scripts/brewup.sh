#!/usr/bin/env zsh

set -euo pipefail

HOME_DIR="${HOME}"
SCRIPT_DIR="${0:A:h}"
ENV_FILE_DEFAULT="${SCRIPT_DIR}/.env"
ENV_FILE="${MACOS_ENV_FILE:-${ENV_FILE_DEFAULT}}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

DEFAULT_BACKUP_ROOT="${HOME_DIR}/.brewthatmac"
BACKUP_ROOT="${MACOS_BACKUP_ROOT:-${DEFAULT_BACKUP_ROOT}}"
REPORTS_DIR="${MACOS_REPORTS_DIR:-${BACKUP_ROOT}/reports}"
MAX_DOCTOR_LOGS="${MACOS_MAX_DOCTOR_LOGS:-20}"
MAX_LOG_DAYS="${MACOS_MAX_LOG_DAYS:-60}"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Lightweight app/package maintenance:
  1) brew update/upgrade
  2) mas upgrade with App Store login prompt + retry
  3) brew cleanup + brew autoremove
  4) brew doctor output to terminal and log file

This script does NOT dump Brewfile, and does NOT run dotfile/system backup.
USAGE
}

step() { printf "\n${C_BLUE}==>${C_RESET} %s\n" "$1"; }
ok() { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
err() { printf "${C_RED}[ERR]${C_RESET} %s\n" "$1"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

prune_pattern_keep_latest() {
  local pattern="$1"
  local keep="$2"
  local -a files
  files=( ${~pattern}(N.om) )
  local count=${#files[@]}

  if (( count > keep )); then
    local remove_count=$((count - keep))
    local f
    for f in "${files[1,${remove_count}]}"; do
      rm -f -- "$f"
    done
  fi
}

try_mas_upgrade_with_login_prompt() {
  command -v mas >/dev/null 2>&1 || {
    warn "mas is not installed; skipping App Store upgrades"
    return 0
  }

  if mas upgrade; then
    ok "mas upgrade complete"
    return 0
  fi

  warn "mas upgrade failed; App Store sign-in may be required"
  if command -v open >/dev/null 2>&1; then
    warn "Opening App Store so you can sign in"
    open -a "App Store" || true
  fi

  if [[ -t 0 ]]; then
    printf "Sign in to App Store, then press Enter to continue... "
    read -r _
  else
    warn "Non-interactive shell detected; cannot wait for sign-in"
  fi

  if mas upgrade; then
    ok "mas upgrade complete after retry"
    return 0
  fi

  warn "mas upgrade still failing; continuing without App Store upgrades"
  warn "You can retry later with: mas upgrade"
  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd brew
mkdir -p "${BACKUP_ROOT}" "${REPORTS_DIR}"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DOCTOR_LOG="${REPORTS_DIR}/brew_doctor_${TIMESTAMP}.log"

step "Updating and upgrading Homebrew"
brew update
brew upgrade
ok "Homebrew update/upgrade complete"

step "Handling Mac App Store upgrades"
try_mas_upgrade_with_login_prompt || true

step "Running Homebrew cleanup"
brew cleanup --prune=all -s
brew autoremove
ok "Cleanup complete"

step "Running Homebrew doctor (output + log)"
set +e
brew doctor 2>&1 | tee "${DOCTOR_LOG}"
doctor_status=${pipestatus[1]}
set -e
if [[ ${doctor_status} -eq 0 ]]; then
  ok "brew doctor clean: ${DOCTOR_LOG}"
else
  warn "brew doctor reported warnings; log saved to ${DOCTOR_LOG}"
fi

step "Pruning doctor log history"
find "${REPORTS_DIR}" -type f -mtime +${MAX_LOG_DAYS} -delete 2>/dev/null || true
prune_pattern_keep_latest "${REPORTS_DIR}/brew_doctor_*.log" "${MAX_DOCTOR_LOGS}"
ok "Retention applied (doctor logs:${MAX_DOCTOR_LOGS}, max age:${MAX_LOG_DAYS}d)"

step "Done"
ok "brewup completed (brew/mas + cleanup + doctor)"
