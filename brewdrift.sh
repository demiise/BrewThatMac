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
BREWDUMP_SCRIPT="${MACOS_BREWDUMP_SCRIPT:-${SCRIPT_DIR}/brewdump.sh}"

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
Usage: $(basename "$0")

Checks drift between installed Homebrew state and Brewfile, then offers actions
based on what is out of sync.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd brew
[[ -f "${BREWFILE_PATH}" ]] || {
  err "Brewfile not found at ${BREWFILE_PATH}"
  exit 1
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
  exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  warn "Non-interactive shell; skipping action menu"
  exit 0
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
      if [[ -x "${BREWDUMP_SCRIPT}" ]]; then
        "${BREWDUMP_SCRIPT}"
      else
        err "brewdump script not found or not executable: ${BREWDUMP_SCRIPT}"
      fi
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
