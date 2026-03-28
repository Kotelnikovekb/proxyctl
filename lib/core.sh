#!/usr/bin/env bash

CONFIG_FILE="/etc/proxyctl/config.env"
STATE_DIR="/var/lib/proxyctl"
THIRDPARTY_DIR="/opt/proxyctl/bin"
THIRDPARTY_MTG_BIN="${THIRDPARTY_DIR}/mtg"
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

detect_host() {
  if [[ -n "${PROXYCTL_PUBLIC_HOST:-}" ]]; then
    echo "${PROXYCTL_PUBLIC_HOST}"
    return
  fi

  local ip
  local first

  first="$(hostname -I 2>/dev/null || true)"
  read -r ip _ <<< "${first}"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return
  fi

  ip="$(curl -4 -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
    return
  fi

  echo "<IP_сервера>"
}
