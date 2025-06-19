# Автоматическая настройка AmneziaWG на OpenWrt

Этот скрипт предназначен **исключительно для автоматической настройки AmneziaWG** на роутерах с OpenWrt. Скрипт автоматически устанавливает и настраивает AmneziaWG туннель без необходимости выбора пользователем - весь трафик автоматически направляется через AWG.

## Возможности скрипта
- Автоматическая установка и настройка AmneziaWG (основное соединение)
- Автоматическая настройка маршрутизации и файрвола
- Поддержка DNS-резолверов (DNSCrypt2, Stubby)
- Загрузка списков доменов для маршрутизации
- **Никаких меню выбора - только AWG туннель**

## Поддерживаемые версии OpenWrt
- OpenWrt 23.05
- OpenWrt 24.10

## Предварительные требования

### 1. Создание GitHub токена
1. Перейдите в [GitHub Settings > Personal Access Tokens](https://github.com/settings/tokens)
2. Создайте новый токен с правами `repo` (для чтения приватных репозиториев)

### 2. Подготовка AWG конфигурации
Создайте файл конфигурации AWG в вашем GitHub репозитории со следующим содержимым:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = ваш_приватный_ключ_клиента
Jc = 5
Jmin = 50
Jmax = 1000
S1 = 86
S2 = 10
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = публичный_ключ_сервера
PresharedKey = предварительно_разделяемый_ключ
Endpoint = ваш.сервер.com:51820
AllowedIPs = 0.0.0.0/0
```

## Установка и настройка

### Быстрый запуск
```bash
sh <(wget -O - https://raw.githubusercontent.com/vpn-config/auto-awg-setup/refs/heads/main/auto_awg.sh)
```

### Пошаговая настройка

1. **Создайте конфигурационный файл на роутере:**
   ```bash
   nano /etc/auto_awg_git.conf
   ```

2. **Добавьте в файл следующее содержимое:**
   ```bash
   # Ваш GitHub токен
   GIT_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   
   # URL к raw файлу конфигурации в GitHub
   REPO_RAW_URL="https://raw.githubusercontent.com/username/repository/branch/path/to/awg.conf"
   ```

3. **Запустите скрипт:**
   ```bash
   sh <(wget -O - https://raw.githubusercontent.com/vpn-config/auto-awg-setup/refs/heads/main/auto_awg.sh)
   ```

## Что делает скрипт

1. **Проверяет систему**: Версию OpenWrt и доступность репозиториев
2. **Устанавливает пакеты AmneziaWG**: 
   - `amneziawg-tools` - утилиты командной строки
   - `kmod-amneziawg` - модуль ядра
   - `luci-app-amneziawg` - веб-интерфейс
3. **Автоматически настраивает AmneziaWG**: 
   - Создает интерфейс awg0
   - Настраивает параметры обфускации (Jc, Jmin, Jmax, S1, S2, H1-H4)
   - Конфигурирует пиры и маршрутизацию
   - **Весь трафик автоматически направляется через AWG туннель**
4. **Настраивает сеть**: 
   - Правила маршрутизации для VPN трафика
   - Зоны и правила firewall
   - Маскарадинг и форвардинг
5. **Настраивает DNS и домены**: 
   - Установка dnsmasq-full
   - Опциональная настройка DNSCrypt2 или Stubby
   - Загрузка списков доменов для селективной маршрутизации

## Режим работы

**AmneziaWG (полный туннель)** - автоматически настраивается:
- Весь трафик идет через AmneziaWG туннель
- Полная анонимизация трафика
- Никаких меню выбора - сразу настройка AWG

## Устранение неполадок

### Ошибка "Failed to parse required AWG configuration values!"

**Причины:**
- Неправильный формат конфигурационного файла AWG
- Отсутствующие обязательные поля
- Проблемы с загрузкой из GitHub

**Решение:**
1. Проверьте формат конфигурационного файла AWG
2. Убедитесь, что все обязательные поля присутствуют:
   - `Address` в секции `[Interface]`
   - `PrivateKey` в секции `[Interface]`
   - `PublicKey` в секции `[Peer]`
   - `Endpoint` в секции `[Peer]`

### Ошибка загрузки конфигурации

**Проверьте:**
- Правильность GitHub токена
- Доступность URL к raw файлу
- Права доступа к репозиторию

### Проблемы с установкой пакетов

**Решение:**
```bash
# Обновите списки пакетов
opkg update

# Синхронизируйте время (если нужно)
ntpd -p ptbtime1.ptb.de
```

## Безопасность

⚠️ **Важно:**
- Храните GitHub токен в безопасности
- Используйте приватные репозитории для конфигураций VPN
- Регулярно ротируйте токены доступа

## Структура проекта

```
auto-awg-setup/
├── auto_awg.sh          # Основной скрипт
└── README.md           # Документация
```

## Поддержка

При возникновении проблем:
1. Проверьте логи: `logread | grep amneziawg`
2. Проверьте статус интерфейса: `ip addr show awg0`
3. Проверьте конфигурацию: `uci show network | grep awg`

## Лицензия

Этот проект распространяется под лицензией MIT.

EXAMPLE awg.conf:
```
[Interface]
Address = 10.8.1.3/32
DNS = 1.1.1.1, 1.0.0.1
PrivateKey = YAEIewtQXHd+wayn3PpPATO6PO0QyPVz4Ho8asJk2yU=
Jc = 2
Jmin = 10
Jmax = 50
S1 = 70
S2 = 86
H1 = 1277409289
H2 = 583382548
H3 = 1924839704
H4 = 1343086294

[Peer]
PublicKey = JFNh/xHiqMSSADhOgLW4padCkWfwxUeu5dscnqoumyI=
PresharedKey = ZrU5pMOuS8STIWTrYFDXytvAppyre3E1Qys7KWWsTMs=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 192.177.26.11:38857
PersistentKeepalive = 25
```