#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ENV_FILE="${MACOS_ENV_FILE:-${SCRIPT_DIR}/.env}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <command>

Commands:
  config  Interactive setup for scripts/.env
  up      Run brew update/upgrade + cleanup + doctor
  dump    Dump installed state to Brewfile + version snapshot
  drift   Audit drift between installed state and Brewfile
  help    Show this help

Examples:
  $(basename "$0") config
  $(basename "$0") up
  $(basename "$0") dump
  $(basename "$0") drift
USAGE
}

cmd="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ "${cmd}" != "help" && "${cmd}" != "-h" && "${cmd}" != "--help" && "${cmd}" != "config" ]]; then
  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      echo "No config file found at ${ENV_FILE}"
      echo "Starting first-run setup..."
      "${SCRIPT_DIR}/brewconfig.sh"
    else
      echo "No config file found at ${ENV_FILE}. Run: $(basename "$0") config" >&2
      exit 1
    fi
  fi
fi

case "${cmd}" in
  config)
    exec "${SCRIPT_DIR}/brewconfig.sh" "$@"
    ;;
  up)
    exec "${SCRIPT_DIR}/brewup.sh" "$@"
    ;;
  dump)
    exec "${SCRIPT_DIR}/brewdump.sh" "$@"
    ;;
  drift)
    exec "${SCRIPT_DIR}/brewdrift.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage >&2
    exit 1
    ;;
esac
