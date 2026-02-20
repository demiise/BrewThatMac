#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
ENV_FILE="${MACOS_ENV_FILE:-${SCRIPT_DIR}/.env}"
HOME_DIR="${HOME}"

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

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} <command>

Commands:
  config  Interactive setup for .env
  up      Run brew update/upgrade + cleanup + doctor
  dump    Dump installed state to Brewfile + version snapshot
  drift   Audit drift between installed state and Brewfile
  help    Show this help

Examples:
  ${SCRIPT_NAME} config
  ${SCRIPT_NAME} up
  ${SCRIPT_NAME} dump
  ${SCRIPT_NAME} drift
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

load_env_if_present() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    source "${ENV_FILE}"
    set +a
  fi
}

init_defaults() {
  DEFAULT_BACKUP_ROOT="${HOME_DIR}/.brewthatmac"
  BACKUP_ROOT="${MACOS_BACKUP_ROOT:-${DEFAULT_BACKUP_ROOT}}"
  BREWFILE_PATH="${MACOS_BREWFILE_PATH:-${BACKUP_ROOT}/Brewfile}"
  REPORTS_DIR="${MACOS_REPORTS_DIR:-${BACKUP_ROOT}/reports}"
  BREWFILE_VERSIONS_DIR="${MACOS_BREWFILE_VERSIONS_DIR:-${BACKUP_ROOT}/versions/brewfile}"
  MAX_DOCTOR_LOGS="${MACOS_MAX_DOCTOR_LOGS:-20}"
  MAX_LOG_DAYS="${MACOS_MAX_LOG_DAYS:-60}"
  MAX_BREWFILE_VERSIONS="${MACOS_MAX_BREWFILE_VERSIONS:-8}"
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

ensure_env_for_runtime() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      warn "No config file found at ${ENV_FILE}"
      warn "Starting first-run setup..."
      cmd_config
    else
      err "No config file found at ${ENV_FILE}. Run: ${SCRIPT_NAME} config"
      exit 1
    fi
  fi
}

cmd_config() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    err "Interactive terminal required for config setup."
    exit 1
  fi

  load_env_if_present
  init_defaults

  default_backup_root="${BACKUP_ROOT}"
  default_brewfile_path="${BREWFILE_PATH}"
  default_reports_dir="${REPORTS_DIR}"
  default_versions_dir="${BREWFILE_VERSIONS_DIR}"
  default_max_doctor_logs="${MAX_DOCTOR_LOGS}"
  default_max_log_days="${MAX_LOG_DAYS}"
  default_max_brewfile_versions="${MAX_BREWFILE_VERSIONS}"

  printf "BrewThatMac configuration\n"
  printf "Press Enter to accept each default.\n\n"

  printf "Backup root [%s]: " "${default_backup_root}"
  read -r input
  backup_root="${input:-$default_backup_root}"

  printf "Brewfile path [%s]: " "${default_brewfile_path}"
  read -r input
  brewfile_path="${input:-$default_brewfile_path}"

  printf "Reports dir [%s]: " "${default_reports_dir}"
  read -r input
  reports_dir="${input:-$default_reports_dir}"

  printf "Brewfile versions dir [%s]: " "${default_versions_dir}"
  read -r input
  versions_dir="${input:-$default_versions_dir}"

  printf "Doctor logs to keep [%s]: " "${default_max_doctor_logs}"
  read -r input
  max_doctor_logs="${input:-$default_max_doctor_logs}"

  printf "Log max age days [%s]: " "${default_max_log_days}"
  read -r input
  max_log_days="${input:-$default_max_log_days}"

  printf "Brewfile versions to keep [%s]: " "${default_max_brewfile_versions}"
  read -r input
  max_brewfile_versions="${input:-$default_max_brewfile_versions}"

  mkdir -p "$(dirname "${ENV_FILE}")"
  cat > "${ENV_FILE}" <<EOF
MACOS_BACKUP_ROOT="${backup_root}"
MACOS_BREWFILE_PATH="${brewfile_path}"
MACOS_REPORTS_DIR="${reports_dir}"
MACOS_BREWFILE_VERSIONS_DIR="${versions_dir}"

MACOS_MAX_DOCTOR_LOGS=${max_doctor_logs}
MACOS_MAX_LOG_DAYS=${max_log_days}
MACOS_MAX_BREWFILE_VERSIONS=${max_brewfile_versions}
EOF

  ok "Wrote config: ${ENV_FILE}"
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

cmd_up() {
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
  ok "brewthatmac up completed"
}

cmd_dump() {
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
}

refresh_drift_quiet() {
  set +e
  brew bundle check --file "${BREWFILE_PATH}" >/dev/null 2>&1
  missing_status=$?
  brew bundle cleanup --file "${BREWFILE_PATH}" >/dev/null 2>&1
  extras_status=$?
  set -e
}

parse_missing_removals() {
  missing_formulae=()
  missing_casks=()
  missing_taps=()

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    if [[ "${line}" =~ '^Formula[[:space:]]+([^[:space:]]+)[[:space:]]+needs to be installed or updated\.$' ]]; then
      missing_formulae+=("${match[1]}")
    elif [[ "${line}" =~ '^Cask[[:space:]]+([^[:space:]]+)[[:space:]]+needs to be installed or updated\.$' ]]; then
      missing_casks+=("${match[1]}")
    elif [[ "${line}" =~ '^Tap[[:space:]]+([^[:space:]]+)[[:space:]]+needs to be installed or updated\.$' ]]; then
      missing_taps+=("${match[1]}")
    fi
  done <<< "${missing_items:-}"
}

cmd_drift() {
  require_cmd brew
  [[ -f "${BREWFILE_PATH}" ]] || {
    err "Brewfile not found at ${BREWFILE_PATH}"
    exit 1
  }

  step "Checking missing dependencies from Brewfile"
  set +e
  missing_output="$(brew bundle check --verbose --file "${BREWFILE_PATH}" 2>&1)"
  missing_status=$?
  set -e
  if [[ ${missing_status} -eq 0 ]]; then
    ok "No missing Brewfile dependencies"
  else
    missing_items="$(printf '%s\n' "${missing_output}" | sed -n -E 's/^→[[:space:]]+(.+)$/\1/p')"
    parse_missing_removals
    if [[ -n "${missing_items}" ]]; then
      warn "Missing entries (quick view):"
      while IFS= read -r item; do
        [[ -z "${item}" ]] && continue
        warn "  - ${item}"
      done <<< "${missing_items}"
      warn "Run to fix: brew bundle install --file \"${BREWFILE_PATH}\""
    else
      warn "Some Brewfile dependencies are missing"
      warn "Run to inspect: brew bundle check --verbose --file \"${BREWFILE_PATH}\""
    fi
  fi

  step "Previewing extras not present in Brewfile"
  set +e
  extras_output="$(brew bundle cleanup --file "${BREWFILE_PATH}" 2>&1)"
  extras_status=$?
  set -e
  if [[ ${extras_status} -eq 0 ]]; then
    ok "No extras detected outside Brewfile"
  else
    extras_items="$(printf '%s\n' "${extras_output}" | awk '
      /^Would uninstall / {capture=1; next}
      /^Run `brew bundle cleanup --force`/ {capture=0}
      capture && NF {print}
    ')"
    if [[ -n "${extras_items}" ]]; then
      warn "Extras detected (quick view):"
      while IFS= read -r item; do
        [[ -z "${item}" ]] && continue
        warn "  - ${item}"
      done <<< "${extras_items}"
      warn "Run to remove: brew bundle cleanup --file \"${BREWFILE_PATH}\" --force"
    else
      warn "Extras detected"
      warn "Run to inspect: brew bundle cleanup --file \"${BREWFILE_PATH}\""
    fi
  fi

  if [[ ${missing_status} -eq 0 && ${extras_status} -eq 0 ]]; then
    ok "No drift detected; exiting"
    return
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "Non-interactive shell; skipping action menu"
    return
  fi

  while true; do
    has_missing=0
    has_extras=0
    [[ ${missing_status} -ne 0 ]] && has_missing=1
    [[ ${extras_status} -ne 0 ]] && has_extras=1

    if [[ ${has_missing} -eq 0 && ${has_extras} -eq 0 ]]; then
      ok "No drift detected; exiting"
      break
    fi

    printf "\nChoose action:\n"
    typeset -A action_map
    option_num=1

    if [[ ${has_missing} -eq 1 ]]; then
      printf "  %d) Match this Mac to Brewfile (install missing apps/tools)\n" "${option_num}"
      action_map[${option_num}]="install_missing"
      option_num=$((option_num + 1))

      printf "  %d) Match Brewfile to this Mac (remove missing entries from Brewfile)\n" "${option_num}"
      action_map[${option_num}]="remove_missing_from_brewfile"
      option_num=$((option_num + 1))
    fi

    if [[ ${has_extras} -eq 1 ]]; then
      printf "  %d) Show extras again (installed here but not in Brewfile)\n" "${option_num}"
      action_map[${option_num}]="preview_extras"
      option_num=$((option_num + 1))

      printf "  %d) Match this Mac to Brewfile (remove extras)\n" "${option_num}"
      action_map[${option_num}]="remove_extras"
      option_num=$((option_num + 1))

      printf "  %d) Keep current installs and update Brewfile to match\n" "${option_num}"
      action_map[${option_num}]="adopt_current"
      option_num=$((option_num + 1))
    fi

    printf "  %d) Exit\n" "${option_num}"
    action_map[${option_num}]="exit"
    printf "> "
    read -r choice
    action="${action_map[${choice}]:-}"

    case "${action}" in
      install_missing)
        step "Installing missing Brewfile entries"
        brew bundle install --file "${BREWFILE_PATH}" --verbose
        ok "Install complete"
        ;;
      remove_missing_from_brewfile)
        step "Removing missing entries from Brewfile"
        parse_missing_removals
        total_removals=$(( ${#missing_formulae[@]} + ${#missing_casks[@]} + ${#missing_taps[@]} ))
        if (( total_removals == 0 )); then
          warn "Could not safely parse removable entries from missing list"
          warn "Open Brewfile to edit manually: ${BREWFILE_PATH}"
        else
          if (( ${#missing_formulae[@]} > 0 )); then
            warn "Formulae to remove:"
            for item in "${missing_formulae[@]}"; do warn "  - ${item}"; done
          fi
          if (( ${#missing_casks[@]} > 0 )); then
            warn "Casks to remove:"
            for item in "${missing_casks[@]}"; do warn "  - ${item}"; done
          fi
          if (( ${#missing_taps[@]} > 0 )); then
            warn "Taps to remove:"
            for item in "${missing_taps[@]}"; do warn "  - ${item}"; done
          fi
          printf "Remove these from Brewfile now? [y/N] "
          read -r confirm
          case "${confirm}" in
            [Yy]|[Yy][Ee][Ss])
              for item in "${missing_formulae[@]}"; do
                brew bundle remove --file "${BREWFILE_PATH}" --formula "${item}"
              done
              for item in "${missing_casks[@]}"; do
                brew bundle remove --file "${BREWFILE_PATH}" --cask "${item}"
              done
              for item in "${missing_taps[@]}"; do
                brew bundle remove --file "${BREWFILE_PATH}" --tap "${item}"
              done
              ok "Brewfile updated; removed parsed missing entries"
              ;;
            *)
              warn "Skipped Brewfile removal"
              ;;
          esac
        fi
        ;;
      preview_extras)
        step "Previewing extras"
        set +e
        preview_output="$(brew bundle cleanup --file "${BREWFILE_PATH}" 2>&1)"
        preview_status=$?
        set -e
        if [[ ${preview_status} -eq 0 ]]; then
          ok "No extras detected"
        else
          preview_items="$(printf '%s\n' "${preview_output}" | awk '
            /^Would uninstall / {capture=1; next}
            /^Run `brew bundle cleanup --force`/ {capture=0}
            capture && NF {print}
          ')"
          if [[ -n "${preview_items}" ]]; then
            warn "Extras detected (quick view):"
            while IFS= read -r item; do
              [[ -z "${item}" ]] && continue
              warn "  - ${item}"
            done <<< "${preview_items}"
          else
            warn "Extras still detected"
          fi
        fi
        ;;
      remove_extras)
        step "Removing extras not in Brewfile"
        printf "This will uninstall items not listed in Brewfile. Continue? [y/N] "
        read -r confirm
        case "${confirm}" in
          [Yy]|[Yy][Ee][Ss])
            brew bundle cleanup --file "${BREWFILE_PATH}" --force
            ok "Cleanup complete"
            ;;
          *)
            warn "Skipped cleanup"
            ;;
        esac
        ;;
      adopt_current)
        step "Adopting current installed state into Brewfile"
        cmd_dump
        ;;
      exit)
        ok "Done"
        break
        ;;
      *)
        warn "Unknown option: ${choice}"
        ;;
    esac

    refresh_drift_quiet
  done
}

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ "${cmd}" != "config" && "${cmd}" != "help" && "${cmd}" != "-h" && "${cmd}" != "--help" ]]; then
  ensure_env_for_runtime
fi

load_env_if_present
init_defaults

case "${cmd}" in
  config)
    cmd_config
    ;;
  up)
    cmd_up
    ;;
  dump)
    cmd_dump
    ;;
  drift)
    cmd_drift
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    err "Unknown command: ${cmd}"
    usage >&2
    exit 1
    ;;
esac
