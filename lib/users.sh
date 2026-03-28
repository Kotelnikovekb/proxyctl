#!/usr/bin/env bash

validate_username() {
  local username="${1:-}"

  if [[ ! "${username}" =~ ^[a-zA-Z0-9._-]{1,32}$ ]]; then
    error "Некорректный username: ${username}"
    error "Разрешены символы: a-z A-Z 0-9 . _ - (до 32 символов)"
    exit 1
  fi
}

validate_password() {
  local password="${1:-}"

  if [[ -z "${password}" ]]; then
    error "Пароль не может быть пустым"
    exit 1
  fi

  if [[ "${password}" == *":"* || "${password}" == *","* ]]; then
    error "Пароль не должен содержать ':' или ','"
    exit 1
  fi
}

user_exists() {
  local username="${1:-}"
  [[ -f "${USER_DB}" ]] && grep -q "^${username}:" "${USER_DB}"
}

get_user_password_interactive() {
  local pass1
  local pass2

  read -r -s -p "Пароль: " pass1
  echo
  read -r -s -p "Повтори пароль: " pass2
  echo

  if [[ "${pass1}" != "${pass2}" ]]; then
    error "Пароли не совпадают"
    exit 1
  fi

  validate_password "${pass1}"
  printf '%s\n' "${pass1}"
}

first_user() {
  if [[ -f "${USER_DB}" && -s "${USER_DB}" ]]; then
    head -n 1 "${USER_DB}" | cut -d':' -f1
  fi
}

reload_3proxy_if_installed() {
  local mode
  mode="$(service_mode)"

  if [[ "${mode}" == "systemd" ]]; then
    if ! service_installed "${SERVICE_3PROXY}"; then
      warn "${SERVICE_3PROXY} не установлен, только обновил пользователей"
      return
    fi

    ensure_3proxy_config
    systemctl restart "${SERVICE_3PROXY}"
    success "${SERVICE_3PROXY} перезапущен"
    return
  fi

  if [[ ! -x "$(process_service_runner_file 3proxy)" ]]; then
    warn "3proxy в process-режиме еще не установлен, только обновил пользователей"
    return
  fi

  ensure_3proxy_config
  start_process_service "3proxy"
  success "3proxy перезапущен (process-режим)"
}

add_user() {
  local username="${1:-}"
  local password

  require_root
  load_config
  ensure_dirs

  if [[ -z "${username}" ]]; then
    error "Использование: proxyctl add-user <username>"
    exit 1
  fi

  validate_username "${username}"

  if user_exists "${username}"; then
    error "Пользователь уже существует: ${username}"
    exit 1
  fi

  password="$(get_user_password_interactive)"

  touch "${USER_DB}"
  chmod 600 "${USER_DB}"
  printf '%s:%s\n' "${username}" "${password}" >> "${USER_DB}"

  reload_3proxy_if_installed
  success "Пользователь добавлен: ${username}"
}

remove_user() {
  local username="${1:-}"
  local tmp_file

  require_root
  load_config
  ensure_dirs

  if [[ -z "${username}" ]]; then
    error "Использование: proxyctl remove-user <username>"
    exit 1
  fi

  validate_username "${username}"

  if ! user_exists "${username}"; then
    error "Пользователь не найден: ${username}"
    exit 1
  fi

  tmp_file="$(mktemp)"
  grep -v "^${username}:" "${USER_DB}" > "${tmp_file}"
  mv "${tmp_file}" "${USER_DB}"
  chmod 600 "${USER_DB}"

  reload_3proxy_if_installed
  success "Пользователь удален: ${username}"
}

list_users() {
  if [[ ! -f "${USER_DB}" || ! -s "${USER_DB}" ]]; then
    echo "Пользователей нет"
    return
  fi

  cut -d':' -f1 "${USER_DB}"
}

change_password() {
  local username="${1:-}"
  local password
  local tmp_file

  require_root
  load_config
  ensure_dirs

  if [[ -z "${username}" ]]; then
    error "Использование: proxyctl change-password <username>"
    exit 1
  fi

  validate_username "${username}"

  if ! user_exists "${username}"; then
    error "Пользователь не найден: ${username}"
    exit 1
  fi

  password="$(get_user_password_interactive)"

  tmp_file="$(mktemp)"
  while IFS= read -r line; do
    if [[ "${line%%:*}" == "${username}" ]]; then
      printf '%s:%s\n' "${username}" "${password}" >> "${tmp_file}"
    else
      printf '%s\n' "${line}" >> "${tmp_file}"
    fi
  done < "${USER_DB}"

  mv "${tmp_file}" "${USER_DB}"
  chmod 600 "${USER_DB}"

  reload_3proxy_if_installed
  success "Пароль обновлен: ${username}"
}
