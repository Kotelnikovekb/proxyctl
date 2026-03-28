#!/usr/bin/env bash
set -euo pipefail

APP_NAME="proxyctl"
INSTALL_DIR="/opt/proxyctl"
BIN_PATH="/usr/local/bin/proxyctl"
CONFIG_DIR="/etc/proxyctl"
LOG_DIR="/var/log/proxyctl"

REPO_OWNER="Kotelnikovekb"
REPO_NAME="proxyctl"
REPO_BRANCH="main"

BASE_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
CLI_FILES=(
  "proxyctl"
  "lib/core.sh"
  "lib/install.sh"
  "lib/users.sh"
  "lib/commands.sh"
)

RUN_WIZARD="${RUN_WIZARD:-true}"

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
    error "Запусти скрипт через sudo или от root"
    exit 1
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  else
    error "Не удалось определить ОС"
    exit 1
  fi

  if [[ "${OS_ID}" != "ubuntu" && "${OS_ID}" != "debian" && "${OS_LIKE}" != *"debian"* ]]; then
    error "Поддерживаются только Ubuntu/Debian"
    exit 1
  fi

  success "Обнаружена ОС: ${PRETTY_NAME:-$OS_ID}"
}

check_command() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  log "Обновляю список пакетов"
  apt-get update -y

local packages=(
  curl
  ca-certificates
)
  log "Устанавливаю зависимости: ${packages[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

  success "Зависимости установлены"
}

create_directories() {
  log "Создаю директории"
  mkdir -p "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}/lib"
  mkdir -p "${CONFIG_DIR}"
  mkdir -p "${LOG_DIR}"

  success "Директории готовы"
}

backup_existing_binary() {
  if [[ -f "${INSTALL_DIR}/proxyctl" ]]; then
    local backup_path="${INSTALL_DIR}/proxyctl.bak.$(date +%s)"
    cp "${INSTALL_DIR}/proxyctl" "${backup_path}"
    warn "Существующий proxyctl сохранен в ${backup_path}"
  fi
}

download_proxyctl() {
  log "Скачиваю proxyctl и модули из GitHub"
  backup_existing_binary

  local file
  local target

  for file in "${CLI_FILES[@]}"; do
    target="${INSTALL_DIR}/${file}"
    mkdir -p "$(dirname "${target}")"
    curl -fsSL "${BASE_RAW_URL}/${file}" -o "${target}"
  done

  chmod +x "${INSTALL_DIR}/proxyctl"

  if [[ ! -s "${INSTALL_DIR}/proxyctl" ]]; then
    error "Файл proxyctl пустой или не скачался"
    exit 1
  fi

  success "proxyctl скачан"
}

create_symlink() {
  log "Создаю symlink ${BIN_PATH}"
  ln -sf "${INSTALL_DIR}/proxyctl" "${BIN_PATH}"
  success "Команда proxyctl доступна как ${BIN_PATH}"
}

write_default_config() {
  local config_file="${CONFIG_DIR}/config.env"

  if [[ ! -f "${config_file}" ]]; then
    log "Создаю базовый config.env"
    cat > "${config_file}" <<'EOF'
# Базовая конфигурация proxyctl
PROXYCTL_CONFIG_VERSION=1
PROXYCTL_DEFAULT_HTTP_PORT=3128
PROXYCTL_DEFAULT_SOCKS_PORT=1080
PROXYCTL_DEFAULT_MTPROTO_PORT=443
PROXYCTL_DATA_DIR=/var/lib/proxyctl
PROXYCTL_MTG_DOMAIN=google.com
PROXYCTL_MTG_VERSION=v2.1.7
EOF
    success "Создан ${config_file}"
  else
    warn "${config_file} уже существует, пропускаю"
  fi
}

check_installed() {
  if ! check_command proxyctl; then
    error "proxyctl не найден в PATH после установки"
    exit 1
  fi

  success "Проверка установки пройдена"
}

print_finish() {
  cat <<EOF

${GREEN}proxyctl установлен.${NC}

Дальше можно выполнить:
  proxyctl wizard
  proxyctl help

Или сразу поставить пресет:
  proxyctl install api
  proxyctl install telegram-mobile
  proxyctl install universal
  proxyctl install mtproto
  proxyctl install full

Если хочешь отключить автозапуск мастера:
  RUN_WIZARD=false curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/install.sh | sudo bash
EOF
}

run_wizard_if_enabled() {
  if [[ "${RUN_WIZARD}" == "true" ]]; then
    echo
    read -r -p "Запустить proxyctl wizard сейчас? [Y/n]: " answer
    answer="${answer:-Y}"

    if [[ "${answer}" =~ ^[Yy]$ ]]; then
      proxyctl wizard || warn "wizard завершился с ошибкой, можешь запустить его позже вручную"
    else
      warn "wizard пропущен"
    fi
  fi
}

main() {
  require_root
  detect_os
  install_packages
  create_directories
  download_proxyctl
  create_symlink
  write_default_config
  check_installed
  print_finish
  run_wizard_if_enabled
}

main "$@"
