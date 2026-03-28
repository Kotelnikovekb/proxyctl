# proxyctl

CLI для быстрой установки и управления proxy-стеком:
- `3proxy` (HTTP + SOCKS5)
- `mtg` (MTProto для Telegram)

`proxyctl` нужен, чтобы за несколько команд поднять прокси на сервере без ручной настройки `3proxy`, `mtg`, systemd-юнитов, конфигов и пользователей. Пакет полезен, если нужно быстро развернуть HTTP/SOCKS5 proxy для API и браузера, выдать доступ пользователям или поднять MTProto-прокси для Telegram.

Telegram-канал автора: https://t.me/kotelnikoff_dev

Поддерживает два режима запуска сервисов:
- `systemd` (обычные серверы/VM)
- `process` (контейнеры без systemd)

## Быстрый старт

```bash
curl -fsSL "https://raw.githubusercontent.com/Kotelnikovekb/proxyctl/main/install.sh" | bash
```

После установки:

```bash
proxyctl wizard
# или сразу
proxyctl install full
```

## Команды

```bash
proxyctl help
proxyctl wizard
proxyctl install <preset> [preset2 ...]
proxyctl add-user <username>
proxyctl remove-user <username>
proxyctl list-users
proxyctl change-password <username>
proxyctl show-connect
proxyctl show-telegram-link
proxyctl restart
proxyctl status
```

## Пресеты

- `api` - 3proxy (HTTP + SOCKS5)
- `telegram-mobile` - 3proxy + MTProto
- `universal` - 3proxy (HTTP + SOCKS5)
- `mtproto` - только MTProto
- `full` - 3proxy + MTProto

## Примеры

```bash
# Установка полного набора
proxyctl install full

# Установка нескольких пресетов сразу
proxyctl install api mtproto
proxyctl install api,mtproto

# Управление пользователями
proxyctl add-user alice
proxyctl list-users
proxyctl change-password alice
proxyctl remove-user alice

# Данные для подключения
proxyctl show-connect
proxyctl show-telegram-link

# Статус и перезапуск
proxyctl status
proxyctl restart
```

## Конфиг

Файл: `/etc/proxyctl/config.env`

Основные параметры:

```env
PROXYCTL_DEFAULT_HTTP_PORT=3128
PROXYCTL_DEFAULT_SOCKS_PORT=1080
PROXYCTL_DEFAULT_MTPROTO_PORT=443
PROXYCTL_MTG_DOMAIN=google.com
PROXYCTL_MTG_VERSION=v2.1.7
PROXYCTL_PUBLIC_HOST=<ваш_ip_или_домен>
PROXYCTL_SERVICE_MODE=auto
```

Пояснения:
- `PROXYCTL_PUBLIC_HOST` используется в `show-connect` и `show-telegram-link`.
- `PROXYCTL_SERVICE_MODE`:
  - `auto` - автоматически `systemd` или `process`
  - `systemd` - принудительно systemd-режим
  - `process` - принудительно process-режим

## Где что хранится

- CLI: `/opt/proxyctl/proxyctl`
- Модули: `/opt/proxyctl/lib/*.sh`
- Бинарники: `/opt/proxyctl/bin`
- Пользователи: `/etc/proxyctl/users.db`
- Конфиг: `/etc/proxyctl/config.env`
- Логи process-режима: `/var/log/proxyctl/*.log`

## Диагностика

```bash
proxyctl status
tail -n 100 /var/log/proxyctl/3proxy.out.log
tail -n 100 /var/log/proxyctl/mtg.out.log
```

Если сборка `3proxy` была из исходников, лог сборки:

```bash
tail -n 100 /var/log/proxyctl/3proxy-build.log
```
