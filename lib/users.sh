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
  local line

  while IFS= read -r line; do
    [[ "${line%%:*}" == "${username}" ]] && return 0
  done < <(user_db_entries)

  return 1
}

get_user_password_interactive() {
  local pass1
  local pass2

  read -r -s -p "Пароль: " pass1
  printf '\n'
  read -r -s -p "Повтори пароль: " pass2
  printf '\n'

  if [[ "${pass1}" != "${pass2}" ]]; then
    error "Пароли не совпадают"
    exit 1
  fi

  validate_password "${pass1}"
  printf '%s\n' "${pass1}"
}

normalize_user_db_or_die() {
  [[ -f "${USER_DB}" ]] || return 0

  local tmp_file
  local line_count
  local valid_count

  tmp_file="$(mktemp)"
  user_db_entries > "${tmp_file}"

  line_count="$(grep -cve '^[[:space:]]*$' -e '^[[:space:]]*#' "${USER_DB}" 2>/dev/null || true)"
  valid_count="$(grep -c . "${tmp_file}" 2>/dev/null || true)"

  if [[ "${line_count}" != "${valid_count}" ]]; then
    rm -f "${tmp_file}"
    error "Файл пользователей поврежден: ${USER_DB}"
    error "Ожидается формат username:password, по одной записи на строку"
    exit 1
  fi

  mv "${tmp_file}" "${USER_DB}"
  chmod 600 "${USER_DB}"
}

first_user() {
  local line

  while IFS= read -r line; do
    printf '%s\n' "${line%%:*}"
    return 0
  done < <(user_db_entries)
}

write_user_db_entries() {
  local tmp_file
  tmp_file="$(mktemp)"
  cat > "${tmp_file}"
  mv "${tmp_file}" "${USER_DB}"
  chmod 600 "${USER_DB}"
}

set_user_password() {
  local username="${1:-}"
  local password="${2:-}"
  local line
  local updated=0

  {
    while IFS= read -r line; do
      if [[ "${line%%:*}" == "${username}" ]]; then
        printf '%s:%s\n' "${username}" "${password}"
        updated=1
      else
        printf '%s\n' "${line}"
      fi
    done < <(user_db_entries)

    if [[ "${updated}" -eq 0 ]]; then
      printf '%s:%s\n' "${username}" "${password}"
    fi
  } | write_user_db_entries
}

delete_user_password() {
  local username="${1:-}"
  local line

  while IFS= read -r line; do
    [[ "${line%%:*}" == "${username}" ]] && continue
    printf '%s\n' "${line}"
  done < <(user_db_entries) | write_user_db_entries
}

resolve_password() {
  local password="${1:-}"

  if [[ -n "${password}" ]]; then
    validate_password "${password}"
    printf '%s\n' "${password}"
    return 0
  fi

  get_user_password_interactive
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

prompt_username_if_missing() {
  local username="${1:-}"
  local prompt="${2:-Username: }"

  if [[ -z "${username}" ]]; then
    read -r -p "${prompt}" username
  fi

  printf '%s\n' "${username}"
}

add_user() {
  local username="${1:-}"
  local password_arg="${2:-}"
  local password

  require_root
  load_config
  ensure_dirs
  normalize_user_db_or_die

  username="$(prompt_username_if_missing "${username}" "Username: ")"

  validate_username "${username}"

  if user_exists "${username}"; then
    error "Пользователь уже существует: ${username}"
    exit 1
  fi

  password="$(resolve_password "${password_arg}")"

  touch "${USER_DB}"
  chmod 600 "${USER_DB}"
  set_user_password "${username}" "${password}"

  reload_3proxy_if_installed
  success "Пользователь добавлен: ${username}"
}

remove_user() {
  local username="${1:-}"

  require_root
  load_config
  ensure_dirs
  normalize_user_db_or_die

  username="$(prompt_username_if_missing "${username}" "Username для удаления: ")"

  validate_username "${username}"

  if ! user_exists "${username}"; then
    error "Пользователь не найден: ${username}"
    exit 1
  fi

  delete_user_password "${username}"

  reload_3proxy_if_installed
  success "Пользователь удален: ${username}"
}

list_users() {
  if [[ ! -f "${USER_DB}" || ! -s "${USER_DB}" ]]; then
    echo "Пользователей нет"
    return
  fi

  user_db_entries | cut -d':' -f1
}

change_password() {
  local username="${1:-}"
  local password_arg="${2:-}"
  local password

  require_root
  load_config
  ensure_dirs
  normalize_user_db_or_die

  username="$(prompt_username_if_missing "${username}" "Username: ")"

  validate_username "${username}"

  if ! user_exists "${username}"; then
    error "Пользователь не найден: ${username}"
    exit 1
  fi

  password="$(resolve_password "${password_arg}")"
  set_user_password "${username}" "${password}"

  reload_3proxy_if_installed
  success "Пароль обновлен: ${username}"
}
