#!/bin/bash

# ==========================================
# SCRIPT: Tier 1 Backup to Google Drive (SMART VERSION)
# DESCRIPTION: Syncs files, but moves deleted items to a history folder
# ==========================================

# --- НАЛАШТУВАННЯ ОТОЧЕННЯ ---
ENV_FILE="/home/ruban/nextcloud/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "CRITICAL: .env файл не знайдено!"
    exit 1
fi

# --- ЗМІННІ ---
TIMESTAMP=$(date +"%d.%m.%Y_%H-%M")
DATE_ONLY=$(date +"%Y-%m-%d") # Тільки дата для папки архіву
LOG_FILE="/var/log/backup_cloud.log"

# Головна папка в хмарі
RCLONE_REMOTE="gdrive:HomeServer_Tier1"
# Папка для "сміття" (Історія видалених файлів)
# Структура буде: HomeServer_Tier1/_History/2025-12-07/...
RCLONE_HISTORY_DIR="$RCLONE_REMOTE/_History/$DATE_ONLY"

# --- ПРОГРАМИ ---
RCLONE_BIN=$(which rclone || echo "/usr/bin/rclone")
RCLONE_CONFIG="/home/ruban/.config/rclone/rclone.conf"

# --- ШЛЯХИ ДО ДАНИХ ---
PATH_CONFIGS="/home/ruban/nextcloud"
PATH_DOCS="/mnt/ssd_storage/Admin_Files/Documents"
PATH_DB_DUMP="/mnt/ssd_storage/Database_Backup"

# --- БАЗА ДАНИХ ---
DB_CONTAINER="nextcloud-db-1"
DB_USER="nextcloud"
DB_PASS="${MYSQL_PASSWORD:?Error: MYSQL_PASSWORD not set in .env}"

# --- ЛОГУВАННЯ ---
log() {
    echo "[$TIMESTAMP] | $1" >> "$LOG_FILE"
    echo "$1"
}

log "INFO | --- Початок SMART бекапу ---"

# --- ПЕРЕВІРКИ ---
if [ ! -f "$RCLONE_CONFIG" ]; then
    log "CRITICAL | Конфіг Rclone не знайдено!"
    exit 1
fi

# 1. БЕКАП БАЗИ
mkdir -p "$PATH_DB_DUMP"
log "INFO | Створення дампа бази..."
docker exec "$DB_CONTAINER" mariadb-dump -u "$DB_USER" -p"$DB_PASS" nextcloud | gzip > "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "SUCCESS | Дамп створено."
    $RCLONE_BIN --config "$RCLONE_CONFIG" copy "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz" "$RCLONE_REMOTE/Database"
    find "$PATH_DB_DUMP" -name "*.sql.gz" -mtime +7 -delete
else
    log "ERROR | Помилка дампа бази!"
fi

# 2. БЕКАП КОНФІГІВ (З захистом від видалення)
log "INFO | Синхронізація конфігурації..."
# Якщо файл видалено локально, в хмарі він переміститься в _History/2025-12-07/Configs
$RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_CONFIGS" "$RCLONE_REMOTE/Configs" \
    --backup-dir "$RCLONE_HISTORY_DIR/Configs" \
    --exclude ".git/**" \
    --exclude "nextcloud_data/**" \
    --exclude "db_data/**" \
    --exclude "homepage/cache/**" \
    --exclude "**/.DS_Store" \
    --transfers 4 --log-file "$LOG_FILE" --log-level ERROR

# 3. БЕКАП ДОКУМЕНТІВ (З захистом від видалення)
log "INFO | Синхронізація документів..."
if [ -d "$PATH_DOCS" ]; then
    # Якщо файл видалено локально, в хмарі він переміститься в _History/2025-12-07/Documents
    $RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_DOCS" "$RCLONE_REMOTE/Documents" \
        --backup-dir "$RCLONE_HISTORY_DIR/Documents" \
        --transfers 4 --log-file "$LOG_FILE" --log-level ERROR
else
    log "WARNING | Папка документів не знайдена."
fi

log "INFO | --- Бекап завершено ---"
