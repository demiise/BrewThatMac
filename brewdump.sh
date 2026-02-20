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
BREWFILE_PATH="${MACOS_BREWFILE_PATH:-${BACKUP_ROOT}/Brewfile}"
BREWFILE_VERSIONS_DIR="${MACOS_BREWFILE_VERSIONS_DIR:-${BACKUP_ROOT}/versions/brewfile}"
MAX_BREWFILE_VERSIONS="${MACOS_MAX_BREWFILE_VERSIONS:-8}"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

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

require_cmd brew
mkdir -p "${BACKUP_ROOT}" "${BREWFILE_VERSIONS_DIR}"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
TEMP_PREV_BREWFILE="$(mktemp -t brewfile_prev.XXXXXX)"
trap 'rm -f "${TEMP_PREV_BREWFILE}"' EXIT

if [[ -f "${BREWFILE_PATH}" ]]; then
  cp "${BREWFILE_PATH}" "${TEMP_PREV_BREWFILE}"
else
  : > "${TEMP_PREV_BREWFILE}"
fi

step "Dumping Brewfile"
brew bundle dump --file "${BREWFILE_PATH}" --describe --force
ok "Brewfile updated at ${BREWFILE_PATH}"

if [[ ! -s "${TEMP_PREV_BREWFILE}" ]] || ! cmp -s "${TEMP_PREV_BREWFILE}" "${BREWFILE_PATH}"; then
  local_version_path="${BREWFILE_VERSIONS_DIR}/Brewfile_${TIMESTAMP}"
  cp "${BREWFILE_PATH}" "${local_version_path}"
  ok "Saved Brewfile version: ${local_version_path}"
else
  warn "Brewfile unchanged; skipped version snapshot"
fi

prune_pattern_keep_latest "${BREWFILE_VERSIONS_DIR}/Brewfile_*" "${MAX_BREWFILE_VERSIONS}"
ok "Retention applied (Brewfile versions:${MAX_BREWFILE_VERSIONS})"
