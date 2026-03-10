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
  edit    Open Brewfile in your preferred editor
  drift   Audit drift between installed state and Brewfile
  shell-hook  Manage optional shell prompt hook for auto-dump
  help    Show this help

Examples:
  ${SCRIPT_NAME} config
  ${SCRIPT_NAME} up
  ${SCRIPT_NAME} dump
  ${SCRIPT_NAME} edit
  ${SCRIPT_NAME} drift
  ${SCRIPT_NAME} shell-hook status
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

snapshot_brew_versions() {
  local type="$1"
  local map_name="$2"
  local line item_name item_version
  local -a lines

  eval "${map_name}=()"
  lines=( "${(@f)$(brew list "--${type}" --versions 2>/dev/null)}" )
  for line in "${lines[@]}"; do
    [[ -n "${line}" ]] || continue
    item_name="${line%% *}"
    if [[ "${line}" == *" "* ]]; then
      item_version="${line#* }"
    else
      item_version=""
    fi
    eval "${map_name}[${(q)item_name}]=${(q)item_version}"
  done
}

snapshot_mas_versions() {
  local version_map_name="$1"
  local name_map_name="$2"
  local line app_id app_name app_version
  local -a lines

  eval "${version_map_name}=()"
  eval "${name_map_name}=()"
  command -v mas >/dev/null 2>&1 || return 0

  lines=( "${(@f)$(mas list 2>/dev/null)}" )
  for line in "${lines[@]}"; do
    if [[ "${line}" =~ '^([0-9]+)[[:space:]]+(.+)[[:space:]]+\(([^()]*)\)$' ]]; then
      app_id="${match[1]}"
      app_name="${match[2]}"
      app_version="${match[3]}"
      eval "${version_map_name}[${(q)app_id}]=${(q)app_version}"
      eval "${name_map_name}[${(q)app_id}]=${(q)app_name}"
    fi
  done
}

print_upgrade_summary() {
  local formula_before_name="$1"
  local formula_after_name="$2"
  local cask_before_name="$3"
  local cask_after_name="$4"
  local mas_versions_before_name="$5"
  local mas_versions_after_name="$6"
  local mas_names_after_name="$7"
  local name before_version after_version app_id app_name
  local -a upgraded_formulae upgraded_casks upgraded_apps
  local -a sorted_formulae sorted_casks sorted_apps

  eval "
    for name in \${(@k)${formula_before_name}}; do
      before_version=\${${formula_before_name}[\$name]}
      after_version=\${${formula_after_name}[\$name]-}
      if [[ -n \"\${after_version}\" && \"\${before_version}\" != \"\${after_version}\" ]]; then
        upgraded_formulae+=( \"\${name} \${before_version} -> \${after_version}\" )
      fi
    done
  "

  eval "
    for name in \${(@k)${cask_before_name}}; do
      before_version=\${${cask_before_name}[\$name]}
      after_version=\${${cask_after_name}[\$name]-}
      if [[ -n \"\${after_version}\" && \"\${before_version}\" != \"\${after_version}\" ]]; then
        upgraded_casks+=( \"\${name} \${before_version} -> \${after_version}\" )
      fi
    done
  "

  eval "
    for app_id in \${(@k)${mas_versions_before_name}}; do
      before_version=\${${mas_versions_before_name}[\$app_id]}
      after_version=\${${mas_versions_after_name}[\$app_id]-}
      if [[ -n \"\${after_version}\" && \"\${before_version}\" != \"\${after_version}\" ]]; then
        app_name=\${${mas_names_after_name}[\$app_id]-App \${app_id}}
        upgraded_apps+=( \"\${app_name} (\${app_id}) \${before_version} -> \${after_version}\" )
      fi
    done
  "

  sorted_formulae=( "${(@on)upgraded_formulae}" )
  sorted_casks=( "${(@on)upgraded_casks}" )
  sorted_apps=( "${(@on)upgraded_apps}" )

  step "Upgrade summary"
  printf "  Homebrew formulae upgraded: %d\n" "${#sorted_formulae[@]}"
  for name in "${sorted_formulae[@]}"; do
    printf "    - %s\n" "${name}"
  done
  printf "  Homebrew casks upgraded: %d\n" "${#sorted_casks[@]}"
  for name in "${sorted_casks[@]}"; do
    printf "    - %s\n" "${name}"
  done
  printf "  App Store apps upgraded: %d\n" "${#sorted_apps[@]}"
  for name in "${sorted_apps[@]}"; do
    printf "    - %s\n" "${name}"
  done
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
  BREWFILE_EDITOR="${MACOS_BREWFILE_EDITOR:-}"
}

escape_env_double_quoted_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf "%s" "${value}"
}

upsert_env_setting() {
  local key="$1"
  local value="$2"
  local escaped_value tmp_file

  escaped_value="$(escape_env_double_quoted_value "${value}")"
  mkdir -p "$(dirname "${ENV_FILE}")"
  [[ -f "${ENV_FILE}" ]] || : > "${ENV_FILE}"
  tmp_file="$(mktemp -t brewthatmac_env.XXXXXX)"

  awk -v key="${key}" -v value="${escaped_value}" '
    BEGIN { wrote = 0 }
    $0 ~ ("^" key "=") {
      if (!wrote) {
        printf "%s=\"%s\"\n", key, value
        wrote = 1
      }
      next
    }
    { print }
    END {
      if (!wrote) {
        printf "%s=\"%s\"\n", key, value
      }
    }
  ' "${ENV_FILE}" > "${tmp_file}"

  mv "${tmp_file}" "${ENV_FILE}"
}

typeset -ga EDITOR_CANDIDATE_LABELS
typeset -ga EDITOR_CANDIDATE_CMDS
CHOSEN_EDITOR_CMD=""

add_editor_candidate() {
  local label="$1"
  local command_str="$2"
  local existing

  for existing in "${EDITOR_CANDIDATE_CMDS[@]:-}"; do
    [[ "${existing}" == "${command_str}" ]] && return
  done

  EDITOR_CANDIDATE_LABELS+=( "${label}" )
  EDITOR_CANDIDATE_CMDS+=( "${command_str}" )
}

collect_editor_candidates() {
  EDITOR_CANDIDATE_LABELS=()
  EDITOR_CANDIDATE_CMDS=()

  command -v cursor >/dev/null 2>&1 && add_editor_candidate "Cursor" "cursor --wait"
  command -v code >/dev/null 2>&1 && add_editor_candidate "VS Code" "code --wait"
  command -v micro >/dev/null 2>&1 && add_editor_candidate "micro" "micro"
  command -v nano >/dev/null 2>&1 && add_editor_candidate "nano" "nano"
  command -v vim >/dev/null 2>&1 && add_editor_candidate "vim" "vim"
  command -v nvim >/dev/null 2>&1 && add_editor_candidate "neovim" "nvim"
  command -v vi >/dev/null 2>&1 && add_editor_candidate "vi" "vi"
  command -v kate >/dev/null 2>&1 && add_editor_candidate "Kate" "kate --block"
  command -v gedit >/dev/null 2>&1 && add_editor_candidate "gedit" "gedit --wait"
  command -v xed >/dev/null 2>&1 && add_editor_candidate "xed" "xed"
  command -v mousepad >/dev/null 2>&1 && add_editor_candidate "mousepad" "mousepad"
  command -v pluma >/dev/null 2>&1 && add_editor_candidate "pluma" "pluma"
  if [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
    add_editor_candidate "TextEdit" "open -W -a TextEdit"
  fi
  command -v notepad.exe >/dev/null 2>&1 && add_editor_candidate "Notepad" "notepad.exe"
  command -v notepad >/dev/null 2>&1 && add_editor_candidate "Notepad" "notepad"
}

resolve_editor_command() {
  local override="${1:-}"
  if [[ -n "${override}" ]]; then
    printf "%s" "${override}"
  elif [[ -n "${BREWFILE_EDITOR:-}" ]]; then
    printf "%s" "${BREWFILE_EDITOR}"
  elif [[ -n "${VISUAL:-}" ]]; then
    printf "%s" "${VISUAL}"
  elif [[ -n "${EDITOR:-}" ]]; then
    printf "%s" "${EDITOR}"
  else
    printf ""
  fi
}

fallback_editor_command() {
  if command -v nano >/dev/null 2>&1; then
    printf "nano"
  elif command -v micro >/dev/null 2>&1; then
    printf "micro"
  elif command -v vim >/dev/null 2>&1; then
    printf "vim"
  elif command -v nvim >/dev/null 2>&1; then
    printf "nvim"
  elif command -v vi >/dev/null 2>&1; then
    printf "vi"
  elif command -v kate >/dev/null 2>&1; then
    printf "kate --block"
  elif command -v gedit >/dev/null 2>&1; then
    printf "gedit --wait"
  elif command -v xed >/dev/null 2>&1; then
    printf "xed"
  elif command -v mousepad >/dev/null 2>&1; then
    printf "mousepad"
  elif command -v pluma >/dev/null 2>&1; then
    printf "pluma"
  elif command -v cursor >/dev/null 2>&1; then
    printf "cursor --wait"
  elif command -v code >/dev/null 2>&1; then
    printf "code --wait"
  elif [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
    printf "open -W -a TextEdit"
  elif command -v notepad.exe >/dev/null 2>&1; then
    printf "notepad.exe"
  elif command -v notepad >/dev/null 2>&1; then
    printf "notepad"
  else
    printf ""
  fi
}

choose_editor_interactively() {
  local option_count index selected_idx answer
  CHOSEN_EDITOR_CMD=""

  [[ -t 0 && -t 1 ]] || return 1
  collect_editor_candidates
  option_count=${#EDITOR_CANDIDATE_CMDS[@]}
  (( option_count > 0 )) || return 1

  step "Choose Brewfile editor"
  for (( index = 1; index <= option_count; index++ )); do
    printf "  %d) %s (%s)\n" \
      "${index}" "${EDITOR_CANDIDATE_LABELS[${index}]}" "${EDITOR_CANDIDATE_CMDS[${index}]}"
  done
  printf "Choose editor [1]: "
  read -r selected_idx
  if [[ -z "${selected_idx}" ]]; then
    selected_idx=1
  fi
  if [[ "${selected_idx}" != <-> ]] || (( selected_idx < 1 || selected_idx > option_count )); then
    warn "Invalid editor selection; skipping interactive picker"
    return 1
  fi

  CHOSEN_EDITOR_CMD="${EDITOR_CANDIDATE_CMDS[${selected_idx}]}"

  printf "Save as default in %s? [Y/n] " "${ENV_FILE}"
  read -r answer
  if [[ -z "${answer}" ]] || ! is_no "${answer}"; then
    upsert_env_setting "MACOS_BREWFILE_EDITOR" "${CHOSEN_EDITOR_CMD}"
    BREWFILE_EDITOR="${CHOSEN_EDITOR_CMD}"
    ok "Saved default editor in ${ENV_FILE}"
  fi
}

run_editor_command() {
  local editor_cmd="$1"
  local file_path="$2"
  local -a editor_parts

  editor_parts=( ${(z)editor_cmd} )
  (( ${#editor_parts[@]} > 0 )) || return 1
  "${editor_parts[@]}" "${file_path}"
}

is_yes() {
  case "${1:-}" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

is_no() {
  case "${1:-}" in
    [Nn]|[Nn][Oo]) return 0 ;;
    *) return 1 ;;
  esac
}

detected_shell_name() {
  local shell_path="${SHELL:-}"
  if [[ -n "${shell_path}" ]]; then
    printf "%s" "${shell_path##*/}"
  else
    printf "unknown"
  fi
}

shell_profile_path() {
  local shell_name="$1"
  case "${shell_name}" in
    zsh)
      printf "%s/.zshrc" "${HOME_DIR}"
      ;;
    bash)
      if [[ -f "${HOME_DIR}/.bashrc" ]]; then
        printf "%s/.bashrc" "${HOME_DIR}"
      elif [[ "${OSTYPE:-}" == darwin* && -f "${HOME_DIR}/.bash_profile" ]]; then
        printf "%s/.bash_profile" "${HOME_DIR}"
      else
        printf "%s/.bashrc" "${HOME_DIR}"
      fi
      ;;
    fish)
      printf "%s/.config/fish/config.fish" "${HOME_DIR}"
      ;;
    *)
      return 1
      ;;
  esac
}

build_shell_hook_block() {
  local shell_name="$1"
  local script_path="${SCRIPT_DIR}/brewthatmac.sh"
  local escaped_script_path="${script_path//\"/\\\"}"

  case "${shell_name}" in
    zsh|bash)
      cat <<EOF
# >>> brewthatmac shell hook >>>
_brewthatmac_script="${escaped_script_path}"
brew() {
  local subcmd="\${1:-}"
  local subsubcmd="\${2:-}"
  local mutating=0
  local state_before=""
  local state_after=""

  case "\${subcmd}" in
    install|reinstall|upgrade|uninstall|remove|rm|tap|untap|pin|unpin|cleanup|autoremove)
      mutating=1
      ;;
    cask)
      case "\${subsubcmd}" in
        install|reinstall|upgrade|uninstall)
          mutating=1
          ;;
      esac
      ;;
  esac

  if [[ \${mutating} -eq 1 ]]; then
    state_before="\$(command brew list --formula --versions 2>/dev/null; command brew list --cask --versions 2>/dev/null)"
  fi

  command brew "\$@"
  local brew_exit_code=\$?

  if [[ \${brew_exit_code} -eq 0 && \${mutating} -eq 1 && -t 0 && -t 1 ]]; then
    state_after="\$(command brew list --formula --versions 2>/dev/null; command brew list --cask --versions 2>/dev/null)"
    if [[ "\${state_before}" != "\${state_after}" ]]; then
      printf "Brew state changed. Dump updated Brewfile now? [y/N] "
      local answer
      read -r answer
      case "\${answer}" in
        [Yy]|[Yy][Ee][Ss])
          local brewthatmac_script="\${_brewthatmac_script:-${escaped_script_path}}"
          "\${brewthatmac_script}" dump || true
          ;;
      esac
    fi
  fi

  return \${brew_exit_code}
}
# <<< brewthatmac shell hook <<<
EOF
      ;;
    fish)
      cat <<EOF
# >>> brewthatmac shell hook >>>
set -g _brewthatmac_script "${escaped_script_path}"
function brew --wraps brew --description "brew with BrewThatMac auto-dump prompt"
  set -l subcmd ""
  set -l subsubcmd ""
  if test (count \$argv) -ge 1
    set subcmd \$argv[1]
  end
  if test (count \$argv) -ge 2
    set subsubcmd \$argv[2]
  end

  set -l mutating 0
  switch "\$subcmd"
    case install reinstall upgrade uninstall remove rm tap untap pin unpin cleanup autoremove
      set mutating 1
    case cask
      switch "\$subsubcmd"
        case install reinstall upgrade uninstall
          set mutating 1
      end
  end

  set -l state_before ""
  set -l state_after ""
  if test \$mutating -eq 1
    set state_before (command brew list --formula --versions 2>/dev/null; command brew list --cask --versions 2>/dev/null)
  end

  command brew \$argv
  set -l brew_exit_code \$status

  if test \$brew_exit_code -eq 0 -a \$mutating -eq 1
    if status is-interactive
      set state_after (command brew list --formula --versions 2>/dev/null; command brew list --cask --versions 2>/dev/null)
      if test "\$state_before" != "\$state_after"
        read -l -P "Brew state changed. Dump updated Brewfile now? [y/N] " answer
        switch "\$answer"
          case y Y yes Yes YES
            set -l brewthatmac_script "\$_brewthatmac_script"
            if test -z "\$brewthatmac_script"
              set brewthatmac_script "${escaped_script_path}"
            end
            "\$brewthatmac_script" dump || true
        end
      end
    end
  end

  return \$brew_exit_code
end
# <<< brewthatmac shell hook <<<
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

upsert_managed_block() {
  local target_file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local block_content="$4"
  local tmp_file begin_line end_line total_lines

  mkdir -p "$(dirname "${target_file}")"
  [[ -f "${target_file}" ]] || : > "${target_file}"
  total_lines="$(wc -l < "${target_file}" | tr -d ' ')"

  begin_line="$(grep -nF "${begin_marker}" "${target_file}" | head -n1 | cut -d: -f1 || true)"
  if [[ -n "${begin_line}" ]]; then
    end_line="$(awk -v start="${begin_line}" -v marker="${end_marker}" 'NR > start && $0 == marker { print NR; exit }' "${target_file}")"
    [[ -n "${end_line}" ]] || end_line="${total_lines}"
    tmp_file="$(mktemp -t brewthatmac_hook_upsert.XXXXXX)"
    if (( begin_line > 1 )); then
      sed -n "1,$((begin_line - 1))p" "${target_file}" > "${tmp_file}"
    else
      : > "${tmp_file}"
    fi
    [[ -s "${tmp_file}" ]] && printf "\n" >> "${tmp_file}"
    printf "%s\n" "${block_content}" >> "${tmp_file}"
    if (( end_line < total_lines )); then
      printf "\n" >> "${tmp_file}"
      sed -n "$((end_line + 1)),\$p" "${target_file}" >> "${tmp_file}"
    fi
    mv "${tmp_file}" "${target_file}"
  else
    tmp_file="$(mktemp -t brewthatmac_hook_append.XXXXXX)"
    cat "${target_file}" > "${tmp_file}"
    [[ -s "${tmp_file}" ]] && printf "\n" >> "${tmp_file}"
    printf "%s\n" "${block_content}" >> "${tmp_file}"
    mv "${tmp_file}" "${target_file}"
  fi
}

remove_managed_block() {
  local target_file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local begin_line end_line total_lines tmp_file

  [[ -f "${target_file}" ]] || return 0
  total_lines="$(wc -l < "${target_file}" | tr -d ' ')"
  begin_line="$(grep -nF "${begin_marker}" "${target_file}" | head -n1 | cut -d: -f1 || true)"
  [[ -n "${begin_line}" ]] || return 0

  end_line="$(awk -v start="${begin_line}" -v marker="${end_marker}" 'NR > start && $0 == marker { print NR; exit }' "${target_file}")"
  [[ -n "${end_line}" ]] || end_line="${total_lines}"

  tmp_file="$(mktemp -t brewthatmac_hook_remove.XXXXXX)"
  if (( begin_line > 1 )); then
    sed -n "1,$((begin_line - 1))p" "${target_file}" > "${tmp_file}"
  else
    : > "${tmp_file}"
  fi
  if (( end_line < total_lines )); then
    [[ -s "${tmp_file}" ]] && printf "\n" >> "${tmp_file}"
    sed -n "$((end_line + 1)),\$p" "${target_file}" >> "${tmp_file}"
  fi
  mv "${tmp_file}" "${target_file}"
}

shell_hook_status_one() {
  local shell_name="$1"
  local target_file
  local begin_marker="# >>> brewthatmac shell hook >>>"

  target_file="$(shell_profile_path "${shell_name}" 2>/dev/null || true)"
  if [[ -z "${target_file}" ]]; then
    warn "${shell_name}: unsupported shell"
    return
  fi
  if [[ -f "${target_file}" ]] && grep -Fq "${begin_marker}" "${target_file}"; then
    ok "${shell_name}: installed (${target_file})"
  else
    warn "${shell_name}: not installed (${target_file})"
  fi
}

install_shell_hook_for_shell() {
  local shell_name="$1"
  local target_file block_content
  local begin_marker="# >>> brewthatmac shell hook >>>"
  local end_marker="# <<< brewthatmac shell hook <<<"

  target_file="$(shell_profile_path "${shell_name}" 2>/dev/null || true)"
  if [[ -z "${target_file}" ]]; then
    warn "Unsupported shell: ${shell_name}"
    return 1
  fi
  block_content="$(build_shell_hook_block "${shell_name}" || true)"
  if [[ -z "${block_content}" ]]; then
    warn "Could not build shell hook for ${shell_name}"
    return 1
  fi
  upsert_managed_block "${target_file}" "${begin_marker}" "${end_marker}" "${block_content}"
  ok "Installed shell hook: ${target_file}"
}

remove_shell_hook_for_shell() {
  local shell_name="$1"
  local target_file
  local begin_marker="# >>> brewthatmac shell hook >>>"
  local end_marker="# <<< brewthatmac shell hook <<<"

  target_file="$(shell_profile_path "${shell_name}" 2>/dev/null || true)"
  if [[ -z "${target_file}" ]]; then
    warn "Unsupported shell: ${shell_name}"
    return 1
  fi
  remove_managed_block "${target_file}" "${begin_marker}" "${end_marker}"
  ok "Removed shell hook (if present): ${target_file}"
}

run_shell_hook_action_for_targets() {
  local action="$1"
  local target="${2:-}"
  local detected shell_name
  local -a targets

  detected="$(detected_shell_name)"
  if [[ -z "${target}" ]]; then
    target="${detected}"
  fi

  if [[ "${target}" == "all" ]]; then
    targets=( zsh bash fish )
  else
    targets=( "${target}" )
  fi

  for shell_name in "${targets[@]}"; do
    case "${action}" in
      install) install_shell_hook_for_shell "${shell_name}" ;;
      remove) remove_shell_hook_for_shell "${shell_name}" ;;
      status) shell_hook_status_one "${shell_name}" ;;
      *)
        err "Unknown shell-hook action: ${action}"
        return 1
        ;;
    esac
  done
}

cmd_shell_hook() {
  local action="${1:-status}"
  local target="${2:-}"

  case "${action}" in
    install|remove|status)
      run_shell_hook_action_for_targets "${action}" "${target}"
      ;;
    *)
      err "Unknown shell-hook action: ${action}"
      warn "Usage: ${SCRIPT_NAME} shell-hook <install|remove|status> [zsh|bash|fish|all]"
      return 1
      ;;
  esac
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
  default_brewfile_editor="${BREWFILE_EDITOR}"

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

  printf "Default Brewfile editor command [%s]: " "${default_brewfile_editor}"
  read -r input
  brewfile_editor="${input:-$default_brewfile_editor}"

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
  if [[ -n "${brewfile_editor}" ]]; then
    escaped_brewfile_editor="$(escape_env_double_quoted_value "${brewfile_editor}")"
    printf 'MACOS_BREWFILE_EDITOR="%s"\n' "${escaped_brewfile_editor}" >> "${ENV_FILE}"
  fi

  ok "Wrote config: ${ENV_FILE}"

  printf "\nEnable shell hook for brew auto-dump? [y/N] "
  read -r input
  if is_yes "${input}"; then
    local detected target_file answer shell_name
    local -a shell_candidates

    printf "When brew installs/upgrades/removes packages and the installed state changed, you'll be prompted to run 'brewthatmac dump'.\n"
    detected="$(detected_shell_name)"
    shell_candidates=( zsh bash fish )

    if target_file="$(shell_profile_path "${detected}" 2>/dev/null)"; then
      printf "Install hook in %s? [Y/n] " "${target_file}"
      read -r answer
      if [[ -z "${answer}" ]] || ! is_no "${answer}"; then
        install_shell_hook_for_shell "${detected}" || true
      fi
    fi

    for shell_name in "${shell_candidates[@]}"; do
      [[ "${shell_name}" == "${detected}" ]] && continue
      target_file="$(shell_profile_path "${shell_name}" 2>/dev/null || true)"
      [[ -n "${target_file}" ]] || continue
      [[ -f "${target_file}" ]] || continue
      printf "Install hook in %s? [y/N] " "${target_file}"
      read -r answer
      if is_yes "${answer}"; then
        install_shell_hook_for_shell "${shell_name}" || true
      fi
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

cmd_up() {
  require_cmd brew
  mkdir -p "${BACKUP_ROOT}" "${REPORTS_DIR}"

  typeset -A formula_versions_before formula_versions_after
  typeset -A cask_versions_before cask_versions_after
  typeset -A mas_versions_before mas_versions_after
  typeset -A mas_names_before mas_names_after

  TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
  DOCTOR_LOG="${REPORTS_DIR}/brew_doctor_${TIMESTAMP}.log"

  step "Collecting pre-upgrade snapshot"
  snapshot_brew_versions "formula" formula_versions_before
  snapshot_brew_versions "cask" cask_versions_before
  snapshot_mas_versions mas_versions_before mas_names_before
  ok "Pre-upgrade snapshot captured"

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

  step "Collecting post-upgrade snapshot"
  snapshot_brew_versions "formula" formula_versions_after
  snapshot_brew_versions "cask" cask_versions_after
  snapshot_mas_versions mas_versions_after mas_names_after
  ok "Post-upgrade snapshot captured"

  print_upgrade_summary \
    formula_versions_before formula_versions_after \
    cask_versions_before cask_versions_after \
    mas_versions_before mas_versions_after mas_names_after

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

cmd_edit() {
  local editor_override=""
  local print_path=0
  local editor_cmd=""

  while (( $# > 0 )); do
    case "$1" in
      --editor)
        shift
        if (( $# == 0 )); then
          err "--editor requires a value"
          return 1
        fi
        editor_override="$1"
        ;;
      --editor=*)
        editor_override="${1#--editor=}"
        ;;
      --print-path)
        print_path=1
        ;;
      *)
        err "Unknown edit option: $1"
        warn "Usage: ${SCRIPT_NAME} edit [--editor \"<command>\"] [--print-path]"
        return 1
        ;;
    esac
    shift
  done

  mkdir -p "$(dirname "${BREWFILE_PATH}")"
  [[ -f "${BREWFILE_PATH}" ]] || : > "${BREWFILE_PATH}"

  if (( print_path == 1 )); then
    printf "%s\n" "${BREWFILE_PATH}"
    return 0
  fi

  editor_cmd="$(resolve_editor_command "${editor_override}")"
  if [[ -z "${editor_cmd}" ]]; then
    choose_editor_interactively || true
    editor_cmd="${CHOSEN_EDITOR_CMD:-}"
  fi
  if [[ -z "${editor_cmd}" ]]; then
    editor_cmd="$(fallback_editor_command)"
  fi

  if [[ -z "${editor_cmd}" ]]; then
    err "No editor found. Set MACOS_BREWFILE_EDITOR, VISUAL, or EDITOR."
    return 1
  fi

  step "Opening Brewfile"
  if ! run_editor_command "${editor_cmd}" "${BREWFILE_PATH}"; then
    err "Failed to launch editor command: ${editor_cmd}"
    return 1
  fi
  ok "Brewfile edit complete: ${BREWFILE_PATH}"
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

if [[ "${cmd}" != "config" && "${cmd}" != "edit" && "${cmd}" != "shell-hook" && "${cmd}" != "help" && "${cmd}" != "-h" && "${cmd}" != "--help" ]]; then
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
  edit)
    cmd_edit "$@"
    ;;
  drift)
    cmd_drift
    ;;
  shell-hook)
    cmd_shell_hook "$@"
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
