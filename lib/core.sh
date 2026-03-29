#!/usr/bin/env bash

CONFIG_FILE="/etc/proxyctl/config.env"
STATE_DIR="/var/lib/proxyctl"
PROXYCTL_HOME="/opt/proxyctl"
THIRDPARTY_DIR="/opt/proxyctl/bin"
THIRDPARTY_MTG_BIN="${THIRDPARTY_DIR}/mtg"
THIRDPARTY_3PROXY_BIN="${THIRDPARTY_DIR}/3proxy"
RUNTIME_DIR="/var/run/proxyctl"
RUNNER_DIR="${PROXYCTL_HOME}/run"
LOG_DIR="/var/log/proxyctl"
SERVICE_3PROXY="proxyctl-3proxy.service"
SERVICE_MTG="proxyctl-mtg.service"
USER_DB="/etc/proxyctl/users.db"

# Значения по умолчанию (могут быть переопределены в /etc/proxyctl/config.env).
PROXYCTL_DEFAULT_HTTP_PORT="3128"
PROXYCTL_DEFAULT_SOCKS_PORT="1080"
PROXYCTL_DEFAULT_MTPROTO_PORT="443"
PROXYCTL_MTG_DOMAIN="google.com"
PROXYCTL_MTG_SECRET=""

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERR]${NC} $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Запусти команду через sudo или от root"
    exit 1
  fi
}

load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    . "${CONFIG_FILE}"
  fi
}

ensure_dirs() {
  mkdir -p /etc/proxyctl
  mkdir -p "${STATE_DIR}"
  mkdir -p "${THIRDPARTY_DIR}"
  mkdir -p "${RUNTIME_DIR}"
  mkdir -p "${RUNNER_DIR}"
  mkdir -p "${LOG_DIR}"
}

require_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    error "systemctl не найден, невозможно управлять сервисами"
    exit 1
  fi

  if [[ ! -d /run/systemd/system ]]; then
    error "systemd не запущен в этой среде"
    exit 1
  fi
}

is_systemd_running() {
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

service_installed() {
  local service="${1:-}"

  if ! is_systemd_running; then
    return 1
  fi

  systemctl list-unit-files | grep -q "^${service}"
}

service_mode() {
  if [[ "${PROXYCTL_SERVICE_MODE:-auto}" == "systemd" ]]; then
    echo "systemd"
    return
  fi

  if [[ "${PROXYCTL_SERVICE_MODE:-auto}" == "process" ]]; then
    echo "process"
    return
  fi

  if is_systemd_running; then
    echo "systemd"
  else
    echo "process"
  fi
}

process_service_pid_file() {
  case "${1:-}" in
    3proxy) echo "${RUNTIME_DIR}/3proxy.pid" ;;
    mtg) echo "${RUNTIME_DIR}/mtg.pid" ;;
    *) return 1 ;;
  esac
}

process_service_runner_file() {
  case "${1:-}" in
    3proxy) echo "${RUNNER_DIR}/run-3proxy.sh" ;;
    mtg) echo "${RUNNER_DIR}/run-mtg.sh" ;;
    *) return 1 ;;
  esac
}

process_service_log_file() {
  case "${1:-}" in
    3proxy) echo "${LOG_DIR}/3proxy.out.log" ;;
    mtg) echo "${LOG_DIR}/mtg.out.log" ;;
    *) return 1 ;;
  esac
}

process_service_running() {
  local service_key="${1:-}"
  local pid_file
  local pid

  pid_file="$(process_service_pid_file "${service_key}")" || return 1
  [[ -f "${pid_file}" ]] || return 1

  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

start_process_service() {
  local service_key="${1:-}"
  local runner
  local pid_file
  local log_file
  local pid

  runner="$(process_service_runner_file "${service_key}")"
  pid_file="$(process_service_pid_file "${service_key}")"
  log_file="$(process_service_log_file "${service_key}")"

  if [[ ! -x "${runner}" ]]; then
    error "Не найден запускатор сервиса: ${runner}"
    exit 1
  fi

  if process_service_running "${service_key}"; then
    stop_process_service "${service_key}"
  fi

  nohup "${runner}" >> "${log_file}" 2>&1 &
  pid="$!"
  echo "${pid}" > "${pid_file}"

  sleep 1
  if ! kill -0 "${pid}" 2>/dev/null; then
    error "Не удалось запустить ${service_key}. Проверь лог: ${log_file}"
    exit 1
  fi

  success "Сервис ${service_key} запущен в process-режиме (pid=${pid})"
}

stop_process_service() {
  local service_key="${1:-}"
  local pid_file
  local pid

  pid_file="$(process_service_pid_file "${service_key}")" || return 0
  [[ -f "${pid_file}" ]] || return 0

  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    sleep 1
    kill -9 "${pid}" 2>/dev/null || true
  fi

  rm -f "${pid_file}"
}

apt_install() {
  local -a packages=("$@")

  if ! command -v apt-get >/dev/null 2>&1; then
    error "Поддерживается только Debian/Ubuntu с apt-get"
    exit 1
  fi

  log "Обновляю индекс пакетов"
  apt-get update -y

  log "Устанавливаю пакеты: ${packages[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

command_path_or_die() {
  local cmd="${1:-}"

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    error "Команда не найдена: ${cmd}"
    exit 1
  fi

  command -v "${cmd}"
}

validate_tcp_port() {
  local port="${1:-}"

  if [[ ! "${port}" =~ ^[0-9]+$ ]] || [[ "${port}" -lt 1 || "${port}" -gt 65535 ]]; then
    error "Некорректный TCP-порт: ${port}"
    exit 1
  fi
}

port_listener_descriptions() {
  local port="${1:-}"

  validate_tcp_port "${port}"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :${port} )" 2>/dev/null | tail -n +2 || true
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | tail -n +2 || true
    return
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null | awk -v port=":${port}" '$4 ~ port"$" {print}' || true
  fi
}

port_owned_by_expected_service() {
  local listeners="${1:-}"
  local service_key="${2:-}"
  local expected_pattern
  local line

  case "${service_key}" in
    3proxy) expected_pattern='3proxy' ;;
    mtg) expected_pattern='mtg' ;;
    *) return 1 ;;
  esac

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    if [[ "${line}" != *"${expected_pattern}"* ]]; then
      return 1
    fi
  done <<< "${listeners}"

  return 0
}

ensure_tcp_port_available_for_service() {
  local port="${1:-}"
  local service_key="${2:-}"
  local listeners

  listeners="$(port_listener_descriptions "${port}")"
  [[ -z "${listeners}" ]] && return

  if port_owned_by_expected_service "${listeners}" "${service_key}"; then
    warn "TCP-порт ${port} уже занят текущим сервисом ${service_key}, продолжаю"
    return
  fi

  error "TCP-порт ${port} уже занят. Освободи порт или измени конфиг:"
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    error "  ${line}"
  done <<< "${listeners}"
  exit 1
}

detect_host() {
  local host

  host="$(detect_public_host_for_config)"
  if [[ -n "${host}" ]]; then
    echo "${host}"
    return
  fi

  echo "<IP_сервера>"
}

detect_public_host_for_config() {
  if [[ -n "${PROXYCTL_PUBLIC_HOST:-}" ]]; then
    echo "${PROXYCTL_PUBLIC_HOST}"
    return
  fi

  local ip
  local first

  ip="$(curl -4 -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return
  fi

  first="$(hostname -I 2>/dev/null || true)"
  read -r ip _ <<< "${first}"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return
  fi
}
