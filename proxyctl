#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
proxyctl commands:
  proxyctl help
  proxyctl wizard
  proxyctl install <preset>
  proxyctl status

presets:
  api
  telegram-mobile
  universal
  mtproto
  full
EOF
}

wizard() {
  echo "ProxyCTL wizard"
  echo "1) API / backend / OpenAI"
  echo "2) Telegram mobile"
  echo "3) Universal"
  echo "4) MTProto"
  echo "5) Full"

  read -r -p "Выбор [1-5]: " choice

  case "${choice}" in
    1) install_preset "api" ;;
    2) install_preset "telegram-mobile" ;;
    3) install_preset "universal" ;;
    4) install_preset "mtproto" ;;
    5) install_preset "full" ;;
    *) echo "Неверный выбор"; exit 1 ;;
  esac
}

install_preset() {
  local preset="${1:-}"

  case "${preset}" in
    api)
      echo "Будет установлен пресет: api"
      ;;
    telegram-mobile)
      echo "Будет установлен пресет: telegram-mobile"
      ;;
    universal)
      echo "Будет установлен пресет: universal"
      ;;
    mtproto)
      echo "Будет установлен пресет: mtproto"
      ;;
    full)
      echo "Будет установлен пресет: full"
      ;;
    *)
      echo "Неизвестный пресет: ${preset}"
      exit 1
      ;;
  esac

  echo "Пока это каркас. Следующим шагом добавим реальную установку 3proxy и MTProto."
}

status() {
  echo "proxyctl installed: yes"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --version >/dev/null 2>&1 || true
  fi
}

cmd="${1:-help}"

case "${cmd}" in
  help|--help|-h) show_help ;;
  wizard) wizard ;;
  install) install_preset "${2:-}" ;;
  status) status ;;
  *) show_help; exit 1 ;;
esac