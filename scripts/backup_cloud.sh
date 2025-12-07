#!/bin/bash

# ==========================================
# SCRIPT: Tier 1 Backup to Google Drive
# AUTHOR: Serg Ruban
# DESCRIPTION: Automates backup of DB, Configs, and Docs with security checks
# ==========================================

# --- НАЛАШТУВАННЯ ОТОЧЕННЯ (БЕЗПЕКА) ---
# Імпортуємо змінні з .env файлу, щоб не світити пароль у скрипті
ENV_FILE="/home/ruban/nextcloud/.env"

if [ -f "$ENV_FILE" ]; then
    # Ця магічна команда читає .env і робить змінні доступними для скрипта
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "CRITICAL: .env файл не знайдено! Паролі відсутні."
    exit 1
fi

# --- ЗМІННІ ---
TIMESTAMP=$(date +"%d.%m.%Y_%H-%M")
LOG_FILE="/var/log/backup_cloud.log"
RCLONE_REMOTE="gdrive:HomeServer_Tier1"

# --- ПРОГРАМИ ---
RCLONE_BIN=$(which rclone || echo "/usr/bin/rclone")
# Шлях до конфігу для роботи від імені root (sudo)
RCLONE_CONFIG="/home/ruban/.config/rclone/rclone.conf"

# --- ШЛЯХИ ДО ДАНИХ (АБСОЛЮТНІ) ---
PATH_CONFIGS="/home/ruban/nextcloud"
PATH_DOCS="/mnt/ssd_storage/Admin_Files/Documents"
PATH_DB_DUMP="/mnt/ssd_storage/Database_Backup"

# --- БАЗА ДАНИХ ---
DB_CONTAINER="nextcloud-db-1"
DB_USER="nextcloud"
# Беремо пароль зі змінної оточення MYSQL_PASSWORD
# Якщо змінної немає — скрипт зупиниться з помилкою
DB_PASS="${MYSQL_PASSWORD:?Error: MYSQL_PASSWORD not set in .env}"

# --- ФУНКЦІЯ ЛОГУВАННЯ ---
log() {
    echo "[$TIMESTAMP] | $1" >> "$LOG_FILE"
    echo "$1"
}

log "INFO | --- Початок хмарного бекапу ---"

# --- ПЕРЕВІРКИ (PRE-FLIGHT) ---
if [ ! -f "$RCLONE_CONFIG" ]; then
    log "CRITICAL | Конфіг Rclone не знайдено: $RCLONE_CONFIG"
    exit 1
fi

# 1. БЕКАП БАЗИ ДАНИХ
mkdir -p "$PATH_DB_DUMP"

log "INFO | Створення дампа бази..."
# Використовуємо -p"$DB_PASS" (без пробілу!)
docker exec "$DB_CONTAINER" mariadb-dump -u "$DB_USER" -p"$DB_PASS" nextcloud | gzip > "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "SUCCESS | Дамп створено та стиснуто."
    
    # Відправка в хмару
    $RCLONE_BIN --config "$RCLONE_CONFIG" copy "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz" "$RCLONE_REMOTE/Database"
    
    # Видаляємо локальні дампи старіші 7 днів
    find "$PATH_DB_DUMP" -name "*.sql.gz" -mtime +7 -delete
else
    log "ERROR | Помилка створення дампа бази!"
fi

# 2. БЕКАП КОНФІГІВ
log "INFO | Синхронізація конфігурації..."
$RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_CONFIGS" "$RCLONE_REMOTE/Configs" \
    --exclude ".git/**" \
    --exclude "nextcloud_data/**" \
    --exclude "db_data/**" \
    --exclude "homepage/cache/**" \
    --exclude "**/.DS_Store" \
    --transfers 4 --log-file "$LOG_FILE" --log-level ERROR

# 3. БЕКАП ДОКУМЕНТІВ
log "INFO | Синхронізація документів..."
if [ -d "$PATH_DOCS" ]; then
    $RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_DOCS" "$RCLONE_REMOTE/Documents" \
        --transfers 4 --log-file "$LOG_FILE" --log-level ERROR
else
    log "WARNING | Папка документів не знайдена."
fi

log "INFO | --- Бекап завершено ---"
