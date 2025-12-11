#!/bin/bash

# ==========================================
# SCRIPT: Tier 1 Backup to Google Drive
# AUTHOR: Serg Ruban
# DESCRIPTION: Automates backup + Telegram Notifications
# ==========================================

# --- НАЛАШТУВАННЯ ОТОЧЕННЯ ---
ENV_FILE="/home/ruban/nextcloud/.env"
NOTIFY_SCRIPT="/home/ruban/nextcloud/scripts/notify.sh"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
else
    echo "CRITICAL: .env файл не знайдено!"
    exit 1
fi

# --- ЗМІННІ ---
TIMESTAMP=$(date +"%d.%m.%Y_%H-%M")
DATE_ONLY=$(date +"%Y-%m-%d")
LOG_FILE="/var/log/backup_cloud.log"

RCLONE_REMOTE="gdrive:HomeServer_Tier1"
RCLONE_HISTORY_DIR="$RCLONE_REMOTE/_History/$DATE_ONLY"

# --- ПРОГРАМИ ---
RCLONE_BIN=$(which rclone || echo "/usr/bin/rclone")
RCLONE_CONFIG="/home/ruban/.config/rclone/rclone.conf"

# --- ШЛЯХИ ---
PATH_CONFIGS="/home/ruban/nextcloud"
PATH_DOCS="/mnt/ssd_storage/Admin_Files/Documents"
PATH_WIFE_DOCS="/mnt/ssd_storage/Wife_Files/Documents"
PATH_DB_DUMP="/mnt/ssd_storage/Database_Backup"

# --- БАЗА ДАНИХ ---
DB_CONTAINER="nextcloud-db-1"
DB_USER="nextcloud"
DB_PASS="${MYSQL_PASSWORD:?Error: MYSQL_PASSWORD not set in .env}"

log() {
    echo "[$TIMESTAMP] | $1" >> "$LOG_FILE"
    echo "$1"
}

# --- ПОЧАТОК ---
log "INFO | --- Початок SMART бекапу ---"
# Сповіщення про старт (можна вимкнути, якщо заважає)
"$NOTIFY_SCRIPT" "🚀 Розпочинаю нічний бекап системи..." "INFO"

if [ ! -f "$RCLONE_CONFIG" ]; then
    MSG="CRITICAL | Конфіг Rclone не знайдено!"
    log "$MSG"
    "$NOTIFY_SCRIPT" "$MSG" "ERROR"
    exit 1
fi

# 1. БЕКАП БАЗИ
mkdir -p "$PATH_DB_DUMP"
log "INFO | Створення дампа бази..."
docker exec "$DB_CONTAINER" mariadb-dump -u "$DB_USER" -p"$DB_PASS" nextcloud | gzip > "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "SUCCESS | Дамп створено."
    
    # shellcheck disable=SC2086
    "$RCLONE_BIN" --config "$RCLONE_CONFIG" copy "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz" "$RCLONE_REMOTE/Database"
    
    find "$PATH_DB_DUMP" -name "*.sql.gz" -mtime +7 -delete
else
    MSG="ERROR | Помилка створення дампа бази даних!"
    log "$MSG"
    "$NOTIFY_SCRIPT" "$MSG" "ERROR"
    # Не виходимо, пробуємо зробити хоча б бекап файлів
fi

# 2. БЕКАП КОНФІГІВ
log "INFO | Синхронізація конфігурації..."
# shellcheck disable=SC2086
"$RCLONE_BIN" --config "$RCLONE_CONFIG" sync "$PATH_CONFIGS" "$RCLONE_REMOTE/Configs" \
    --backup-dir "$RCLONE_HISTORY_DIR/Configs" \
    --exclude ".git/**" \
    --exclude "nextcloud_data/**" \
    --exclude "db_data/**" \
    --exclude "homepage/cache/**" \
    --exclude "**/.DS_Store" \
    --transfers 4 --log-file "$LOG_FILE" --log-level ERROR

# 3. БЕКАП ДОКУМЕНТІВ (ADMIN)
if [ -d "$PATH_DOCS" ]; then
    # shellcheck disable=SC2086
    "$RCLONE_BIN" --config "$RCLONE_CONFIG" sync "$PATH_DOCS" "$RCLONE_REMOTE/Documents" \
        --backup-dir "$RCLONE_HISTORY_DIR/Documents" \
        --transfers 4 --log-file "$LOG_FILE" --log-level ERROR
fi

# 4. БЕКАП ДОКУМЕНТІВ (WIFE)
if [ -d "$PATH_WIFE_DOCS" ]; then
    # shellcheck disable=SC2086
    "$RCLONE_BIN" --config "$RCLONE_CONFIG" sync "$PATH_WIFE_DOCS" "$RCLONE_REMOTE/Documents_Wife" \
        --backup-dir "$RCLONE_HISTORY_DIR/Documents_Wife" \
        --transfers 4 --log-file "$LOG_FILE" --log-level ERROR
fi

log "INFO | --- Бекап завершено ---"
"$NOTIFY_SCRIPT" "✅ Бекап успішно завершено! Файли в хмарі." "SUCCESS"
