#!/usr/bin/env bash

build_3proxy_auth_block() {
  if [[ ! -f "${USER_DB}" || ! -s "${USER_DB}" ]]; then
    cat <<'EOF_AUTH'
# Режим без авторизации (нет пользователей в proxyctl).
auth none
allow *
EOF_AUTH
    return
  fi

  local entries=""
  local line
  local username
  local password

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    username="${line%%:*}"
    password="${line#*:}"

    if [[ -n "${entries}" ]]; then
      entries+=","
    fi
    entries+="${username}:CL:${password}"
  done < "${USER_DB}"

  cat <<EOF_AUTH
# Режим с авторизацией пользователей proxyctl.
auth strong
users ${entries}
allow *
EOF_AUTH
}

ensure_3proxy_config() {
  local config_path="/etc/3proxy/3proxy.cfg"
  local auth_block

  mkdir -p /etc/3proxy
  auth_block="$(build_3proxy_auth_block)"

  cat > "${config_path}" <<EOF_3P
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
maxconn 2000
setgid 65534
setuid 65534
flush

log /var/log/3proxy/3proxy.log D
rotate 30

${auth_block}

proxy -n -a -p${PROXYCTL_DEFAULT_HTTP_PORT}
socks -n -a -p${PROXYCTL_DEFAULT_SOCKS_PORT}
EOF_3P

  mkdir -p /var/log/3proxy
  touch /var/log/3proxy/3proxy.log
  chown -R 65534:65534 /var/log/3proxy
  success "Сконфигурирован /etc/3proxy/3proxy.cfg"
}

ensure_3proxy_service() {
  local mode
  local proxy_bin
  local runner

  mode="$(service_mode)"
  proxy_bin="$(resolve_3proxy_bin)"

  if [[ "${mode}" == "systemd" ]]; then
    cat > "/etc/systemd/system/${SERVICE_3PROXY}" <<EOF_SVC
[Unit]
Description=ProxyCTL 3proxy service
After=network.target

[Service]
Type=simple
ExecStart=${proxy_bin} /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_SVC

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_3PROXY}"
    success "Сервис ${SERVICE_3PROXY} запущен"
    return
  fi

  runner="$(process_service_runner_file 3proxy)"
  cat > "${runner}" <<EOF_RUN
#!/usr/bin/env bash
exec ${proxy_bin} /etc/3proxy/3proxy.cfg
EOF_RUN
  chmod +x "${runner}"

  start_process_service "3proxy"
}

install_3proxy_from_source() {
  local ref="${PROXYCTL_3PROXY_REF:-master}"
  local build_dir
  local repo_url="https://github.com/3proxy/3proxy.git"

  log "Собираю 3proxy из исходников (${repo_url}, ref=${ref})"
  apt_install git build-essential make gcc libc6-dev

  build_dir="$(mktemp -d /tmp/proxyctl-3proxy-build.XXXXXX)"
  git clone --depth 1 --branch "${ref}" "${repo_url}" "${build_dir}"
  make -C "${build_dir}" -f Makefile.Linux

  if [[ ! -x "${build_dir}/bin/3proxy" ]]; then
    error "Сборка 3proxy завершилась без бинарника ${build_dir}/bin/3proxy"
    exit 1
  fi

  install -m 0755 "${build_dir}/bin/3proxy" "${THIRDPARTY_3PROXY_BIN}"
  rm -rf "${build_dir}"
  success "3proxy установлен из исходников в ${THIRDPARTY_3PROXY_BIN}"
}

resolve_3proxy_bin() {
  if command -v 3proxy >/dev/null 2>&1; then
    command -v 3proxy
    return
  fi

  if [[ -x "${THIRDPARTY_3PROXY_BIN}" ]]; then
    echo "${THIRDPARTY_3PROXY_BIN}"
    return
  fi

  error "Бинарник 3proxy не найден"
  exit 1
}

install_3proxy_stack() {
  local mode

  mode="$(service_mode)"
  if ! command -v apt-get >/dev/null 2>&1; then
    error "Поддерживается только Debian/Ubuntu с apt-get"
    exit 1
  fi

  log "Обновляю индекс пакетов"
  apt-get update -y

  if ! command -v 3proxy >/dev/null 2>&1 && [[ ! -x "${THIRDPARTY_3PROXY_BIN}" ]]; then
    log "Пробую установить пакет 3proxy из репозитория"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y 3proxy; then
      success "Пакет 3proxy установлен из репозитория"
    else
      warn "Пакет 3proxy недоступен в репозитории. Перехожу на сборку из исходников."
      install_3proxy_from_source
    fi
  fi

  if [[ "${mode}" == "systemd" ]] && systemctl list-unit-files | grep -q "^3proxy\\.service"; then
    systemctl disable --now 3proxy.service >/dev/null 2>&1 || true
  fi

  ensure_3proxy_config
  ensure_3proxy_service
}

mtg_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) error "Неподдерживаемая архитектура для mtg: $(uname -m)"; exit 1 ;;
  esac
}

ensure_mtg_binary() {
  local version="${PROXYCTL_MTG_VERSION:-v2.1.7}"
  local version_no_v
  local arch
  local direct_url
  local archive_url
  local tmp_dir
  local archive_path
  local extracted_bin

  arch="$(mtg_arch)"
  version_no_v="${version#v}"
  direct_url="https://github.com/9seconds/mtg/releases/download/${version}/mtg-linux-${arch}"
  archive_url="https://github.com/9seconds/mtg/releases/download/${version}/mtg-${version_no_v}-linux-${arch}.tar.gz"

  log "Скачиваю mtg (${version}, ${arch})"

  if curl -fsSL "${direct_url}" -o "${THIRDPARTY_MTG_BIN}"; then
    chmod +x "${THIRDPARTY_MTG_BIN}"
    success "mtg установлен в ${THIRDPARTY_MTG_BIN}"
    return
  fi

  command_path_or_die tar >/dev/null
  tmp_dir="$(mktemp -d /tmp/proxyctl-mtg.XXXXXX)"
  archive_path="${tmp_dir}/mtg.tar.gz"

  curl -fsSL "${archive_url}" -o "${archive_path}"
  tar -xzf "${archive_path}" -C "${tmp_dir}"

  extracted_bin="$(find "${tmp_dir}" -maxdepth 1 -type f -name "mtg-*-linux-${arch}" | head -n 1)"
  if [[ -z "${extracted_bin}" ]]; then
    error "Не удалось найти бинарник mtg в архиве ${archive_url}"
    exit 1
  fi

  install -m 0755 "${extracted_bin}" "${THIRDPARTY_MTG_BIN}"
  rm -rf "${tmp_dir}"
  success "mtg установлен в ${THIRDPARTY_MTG_BIN}"
}

ensure_mtg_secret() {
  if [[ -z "${PROXYCTL_MTG_SECRET}" ]]; then
    PROXYCTL_MTG_SECRET="$(openssl rand -hex 16)"
    warn "Сгенерирован новый MTProto secret: ${PROXYCTL_MTG_SECRET}"
    warn "Сохрани его: это значение нужно клиентам Telegram"
    {
      echo ""
      echo "# Автосгенерировано proxyctl $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "PROXYCTL_MTG_SECRET=${PROXYCTL_MTG_SECRET}"
    } >> "${CONFIG_FILE}"
  fi
}

ensure_mtg_service() {
  local mode
  local runner

  mode="$(service_mode)"

  if [[ "${mode}" == "systemd" ]]; then
    cat > "/etc/systemd/system/${SERVICE_MTG}" <<EOF_MTG
[Unit]
Description=ProxyCTL MTProto service (mtg)
After=network.target

[Service]
Type=simple
ExecStart=${THIRDPARTY_MTG_BIN} run --bind 0.0.0.0:${PROXYCTL_DEFAULT_MTPROTO_PORT} ${PROXYCTL_MTG_SECRET} ${PROXYCTL_MTG_DOMAIN}:443
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_MTG

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_MTG}"
    success "Сервис ${SERVICE_MTG} запущен"
    return
  fi

  runner="$(process_service_runner_file mtg)"
  cat > "${runner}" <<EOF_RUN
#!/usr/bin/env bash
exec ${THIRDPARTY_MTG_BIN} run --bind 0.0.0.0:${PROXYCTL_DEFAULT_MTPROTO_PORT} ${PROXYCTL_MTG_SECRET} ${PROXYCTL_MTG_DOMAIN}:443
EOF_RUN
  chmod +x "${runner}"

  start_process_service "mtg"
}

install_mtproto_stack() {
  apt_install curl ca-certificates openssl
  ensure_mtg_binary
  ensure_mtg_secret
  ensure_mtg_service

  cat <<EOF_HINT

MTProto данные для клиента:
  host: <IP_сервера>
  port: ${PROXYCTL_DEFAULT_MTPROTO_PORT}
  secret: ${PROXYCTL_MTG_SECRET}
  domain (fake-tls): ${PROXYCTL_MTG_DOMAIN}
EOF_HINT
}

install_preset() {
  local preset="${1:-}"

  require_root
  load_config
  ensure_dirs

  case "${preset}" in
    api)
      log "Установка пресета: api"
      install_3proxy_stack
      ;;
    telegram-mobile)
      log "Установка пресета: telegram-mobile"
      install_3proxy_stack
      install_mtproto_stack
      ;;
    universal)
      log "Установка пресета: universal"
      install_3proxy_stack
      ;;
    mtproto)
      log "Установка пресета: mtproto"
      install_mtproto_stack
      ;;
    full)
      log "Установка пресета: full"
      install_3proxy_stack
      install_mtproto_stack
      ;;
    *)
      error "Неизвестный пресет: ${preset}"
      exit 1
      ;;
  esac

  success "Пресет ${preset} установлен"
}

choice_to_preset() {
  local choice="${1:-}"

  case "${choice}" in
    1) echo "api" ;;
    2) echo "telegram-mobile" ;;
    3) echo "universal" ;;
    4) echo "mtproto" ;;
    5) echo "full" ;;
    *) return 1 ;;
  esac
}

wizard_multiselect_whiptail() {
  local selected
  local -a chosen=()
  local choice

  selected=$(
    whiptail --title "ProxyCTL wizard" \
      --checklist "Выбери пресеты (Space = выбрать, Enter = подтвердить):" \
      20 72 10 \
      "1" "API / backend / OpenAI" OFF \
      "2" "Telegram mobile" OFF \
      "3" "Universal" OFF \
      "4" "MTProto" OFF \
      "5" "Full" OFF \
      3>&1 1>&2 2>&3
  ) || return 1

  selected="${selected//\"/}"

  for choice in ${selected}; do
    chosen+=("$(choice_to_preset "${choice}")")
  done

  if [[ "${#chosen[@]}" -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${chosen[@]}"
}

wizard() {
  echo "ProxyCTL wizard"
  local -a presets_to_install=()

  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    local preset
    while IFS= read -r preset; do
      presets_to_install+=("${preset}")
    done < <(wizard_multiselect_whiptail)
  else
    echo "1) API / backend / OpenAI"
    echo "2) Telegram mobile"
    echo "3) Universal"
    echo "4) MTProto"
    echo "5) Full"
    echo "Можно выбрать несколько: 1,3,4 или 1 3 4"

    local choices_raw
    local token
    local preset
    local -A seen=()

    read -r -p "Выбор [1-5]: " choices_raw
    choices_raw="${choices_raw//,/ }"

    for token in ${choices_raw}; do
      if ! preset="$(choice_to_preset "${token}")"; then
        error "Неверный выбор: ${token}"
        exit 1
      fi

      if [[ -z "${seen[${preset}]:-}" ]]; then
        presets_to_install+=("${preset}")
        seen["${preset}"]=1
      fi
    done
  fi

  if [[ "${#presets_to_install[@]}" -eq 0 ]]; then
    error "Ничего не выбрано"
    exit 1
  fi

  for preset in "${presets_to_install[@]}"; do
    install_preset "${preset}"
  done
}

install_from_args() {
  if [[ "$#" -eq 0 ]]; then
    error "Укажи хотя бы один пресет: proxyctl install <preset> [preset2 ...]"
    exit 1
  fi

  local arg
  local item

  for arg in "$@"; do
    arg="${arg//,/ }"
    for item in ${arg}; do
      install_preset "${item}"
    done
  done
}
