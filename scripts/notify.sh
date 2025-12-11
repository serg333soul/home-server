#!/bin/bash

# ========================================================
# SCRIPT: Telegram Notification Utility
# DESCRIPTION: Відправляє повідомлення в Телеграм
# USAGE: ./notify.sh "Текст повідомлення" "STATUS"
# ========================================================

MESSAGE="$1"
TYPE="${2:-INFO}"

# 1. Завантаження секретів
ENV_FILE="/home/ruban/nextcloud/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # FIX SC1090: Кажемо ShellCheck ігнорувати невідоме джерело
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
else
    echo "❌ CRITICAL: Не знайдено файл .env"
    exit 1
fi

# 2. Перевірка змінних
if [[ -z "$TELEGRAM_BOT_TOKEN" ]] || [[ -z "$TELEGRAM_CHAT_ID" ]]; then
    echo "❌ CRITICAL: Токени не задані в .env"
    exit 1
fi

# 3. Вибір іконки
case "$TYPE" in
    "ERROR")   ICON="🚨 ПОМИЛКА" ;;
    "SUCCESS") ICON="✅ УСПІХ" ;;
    "WARNING") ICON="⚠️ УВАГА" ;;
    *)         ICON="ℹ️ ІНФО" ;;
esac

# 4. Форматування
FULL_TEXT="*Server Notification* [Home]%0A--------------------------------%0A*$ICON*%0A$MESSAGE"

# 5. Відправка
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="Markdown" \
    --data-urlencode text="$FULL_TEXT" > /dev/null
