#!/usr/bin/env bash

show_help() {
  cat <<'EOF_HELP'
proxyctl commands:
  proxyctl help                          - показать эту справку
  proxyctl wizard                        - интерактивный выбор и установка пресетов
  proxyctl install <preset> [preset2 ...] - установить один или несколько пресетов
  proxyctl add-user <username>           - добавить пользователя для HTTP/SOCKS авторизации
  proxyctl remove-user <username>        - удалить пользователя
  proxyctl list-users                    - список пользователей
  proxyctl change-password <username>    - сменить пароль пользователя
  proxyctl show-connect                  - показать параметры HTTP/SOCKS подключения
  proxyctl show-telegram-link            - показать tg:// ссылку для MTProto
  proxyctl restart                       - перезапустить сервисы proxyctl
  proxyctl status                        - статус сервисов, конфигурации и пользователей

presets:
  api              - 3proxy (HTTP + SOCKS5)
  telegram-mobile  - 3proxy + MTProto
  universal        - 3proxy (HTTP + SOCKS5)
  mtproto          - только MTProto
  full             - 3proxy + MTProto

examples:
  proxyctl install full
  proxyctl install api mtproto
  proxyctl add-user alice
  proxyctl list-users
  proxyctl show-connect
  proxyctl show-telegram-link
  proxyctl status
EOF_HELP
}

show_connect() {
  load_config

  local host
  local username
  host="$(detect_host)"
  username="$(first_user || true)"
  username="${username:-<username>}"

  cat <<EOF_CONNECT
HTTP Proxy:
  host: ${host}
  port: ${PROXYCTL_DEFAULT_HTTP_PORT}
  username: ${username}

SOCKS5 Proxy:
  host: ${host}
  port: ${PROXYCTL_DEFAULT_SOCKS_PORT}
  username: ${username}
EOF_CONNECT
}

show_telegram_link() {
  load_config

  if [[ -z "${PROXYCTL_MTG_SECRET}" ]]; then
    error "MTProto secret не найден. Установи пресет mtproto/full или укажи PROXYCTL_MTG_SECRET в ${CONFIG_FILE}"
    exit 1
  fi

  local host
  host="$(detect_host)"

  echo "tg://proxy?server=${host}&port=${PROXYCTL_DEFAULT_MTPROTO_PORT}&secret=${PROXYCTL_MTG_SECRET}"
}

restart_services() {
  require_root
  local mode
  mode="$(service_mode)"

  local restarted=0

  if [[ "${mode}" == "systemd" ]]; then
    if service_installed "${SERVICE_3PROXY}"; then
      systemctl restart "${SERVICE_3PROXY}"
      success "Перезапущен ${SERVICE_3PROXY}"
      restarted=1
    fi

    if service_installed "${SERVICE_MTG}"; then
      systemctl restart "${SERVICE_MTG}"
      success "Перезапущен ${SERVICE_MTG}"
      restarted=1
    fi
  else
    if [[ -x "$(process_service_runner_file 3proxy)" ]]; then
      start_process_service "3proxy"
      restarted=1
    fi

    if [[ -x "$(process_service_runner_file mtg)" ]]; then
      start_process_service "mtg"
      restarted=1
    fi
  fi

  if [[ "${restarted}" -eq 0 ]]; then
    warn "Нет установленных сервисов proxyctl для перезапуска"
  fi
}

service_status_line() {
  local service="${1:-}"
  local mode
  mode="$(service_mode)"

  if [[ "${mode}" == "process" ]]; then
    local key
    if [[ "${service}" == "${SERVICE_3PROXY}" ]]; then
      key="3proxy"
    elif [[ "${service}" == "${SERVICE_MTG}" ]]; then
      key="mtg"
    else
      echo "${service}: unknown"
      return
    fi

    if process_service_running "${key}"; then
      echo "${service}: active (process mode)"
    elif [[ -x "$(process_service_runner_file "${key}")" ]]; then
      echo "${service}: installed, not active (process mode)"
    else
      echo "${service}: not installed (process mode)"
    fi
    return
  fi

  if systemctl is-active --quiet "${service}"; then
    echo "${service}: active"
  elif systemctl list-unit-files | grep -q "^${service}"; then
    echo "${service}: installed, not active"
  else
    echo "${service}: not installed"
  fi
}

status() {
  load_config

  echo "proxyctl status"
  echo "mode: $(service_mode)"
  service_status_line "${SERVICE_3PROXY}"
  service_status_line "${SERVICE_MTG}"

  if [[ -f "${CONFIG_FILE}" ]]; then
    echo "config: ${CONFIG_FILE}"
  else
    echo "config: not found (${CONFIG_FILE})"
  fi

  if [[ -f "${USER_DB}" ]]; then
    echo "users: $(wc -l < "${USER_DB}" | tr -d ' ')"
  else
    echo "users: 0"
  fi
}
