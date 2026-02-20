#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ENV_FILE="${MACOS_ENV_FILE:-${SCRIPT_DIR}/.env}"

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Interactive terminal required for config setup." >&2
  exit 1
fi

default_backup_root="${MACOS_BACKUP_ROOT:-$HOME/.brewthatmac}"
default_brewfile_path="${MACOS_BREWFILE_PATH:-${default_backup_root}/Brewfile}"
default_reports_dir="${MACOS_REPORTS_DIR:-${default_backup_root}/reports}"
default_versions_dir="${MACOS_BREWFILE_VERSIONS_DIR:-${default_backup_root}/versions/brewfile}"
if [[ -n "${MACOS_BREWDUMP_SCRIPT:-}" && -x "${MACOS_BREWDUMP_SCRIPT}" ]]; then
  default_dump_script="${MACOS_BREWDUMP_SCRIPT}"
else
  default_dump_script="${SCRIPT_DIR}/brewdump.sh"
fi
default_max_doctor_logs="${MACOS_MAX_DOCTOR_LOGS:-20}"
default_max_log_days="${MACOS_MAX_LOG_DAYS:-60}"
default_max_brewfile_versions="${MACOS_MAX_BREWFILE_VERSIONS:-8}"

echo "BrewThatMac configuration"
echo "Press Enter to accept each default."
echo

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

printf "Brew dump script path [%s]: " "${default_dump_script}"
read -r input
dump_script="${input:-$default_dump_script}"

mkdir -p "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<EOF
MACOS_BACKUP_ROOT="${backup_root}"
MACOS_BREWFILE_PATH="${brewfile_path}"
MACOS_REPORTS_DIR="${reports_dir}"
MACOS_BREWFILE_VERSIONS_DIR="${versions_dir}"
MACOS_BREWDUMP_SCRIPT="${dump_script}"

MACOS_MAX_DOCTOR_LOGS=${max_doctor_logs}
MACOS_MAX_LOG_DAYS=${max_log_days}
MACOS_MAX_BREWFILE_VERSIONS=${max_brewfile_versions}
EOF

echo
echo "Wrote config: ${ENV_FILE}"
