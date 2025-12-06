#!/bin/bash

# ==========================================
# SCRIPT: Tier 1 Backup to Google Drive (ROOT FIX)
# ==========================================

# --- ЗМІННІ ---
TIMESTAMP=$(date +"%d.%m.%Y_%H-%M")
LOG_FILE="/var/log/backup_cloud.log"
RCLONE_REMOTE="gdrive:HomeServer_Tier1"

# --- ШЛЯХИ ДО ПРОГРАМ ---
# Знаходимо де rclone (якщо which не спрацює, спробуємо стандартні шляхи)
RCLONE_BIN=$(which rclone || echo "/usr/bin/rclone")

# --- КОНФІГУРАЦІЯ RCLONE (КРИТИЧНО ВАЖЛИВО) ---
# Ми вказуємо шлях до файлу користувача ruban, щоб root міг його читати
RCLONE_CONFIG="/home/ruban/.config/rclone/rclone.conf"

# --- ШЛЯХИ ДО ДАНИХ ---
PATH_CONFIGS="/home/ruban/nextcloud"
PATH_DOCS="/mnt/ssd_storage/Admin_Files/Documents"
PATH_DB_DUMP="/mnt/ssd_storage/Database_Backup"

# --- БАЗА ДАНИХ ---
DB_CONTAINER="nextcloud-db-1"
DB_USER="nextcloud"
# 👇 ВСТАВТЕ СЮДИ ПАРОЛЬ З ФАЙЛУ .env
DB_PASS="MySecretNextcloudPassword" 

# --- ЛОГУВАННЯ ---
log() {
    echo "[$TIMESTAMP] | $1" >> "$LOG_FILE"
    echo "$1"
}

log "INFO | --- Початок хмарного бекапу ---"

# --- ПЕРЕВІРКИ ПЕРЕД СТАРТОМ ---
if [ ! -f "$RCLONE_CONFIG" ]; then
    log "CRITICAL | Файл конфігурації Rclone не знайдено: $RCLONE_CONFIG"
    exit 1
fi

if [ -z "$DB_PASS" ]; then
    log "CRITICAL | Не вказано пароль бази даних (DB_PASS)!"
    exit 1
fi

# 1. БЕКАП БАЗИ
mkdir -p "$PATH_DB_DUMP"

log "INFO | Створення дампа бази..."
docker exec "$DB_CONTAINER" mariadb-dump -u "$DB_USER" -p"$DB_PASS" nextcloud | gzip > "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "SUCCESS | Дамп створено."
    
    # ВІДПРАВКА: Зверніть увагу на прапорець --config
    $RCLONE_BIN --config "$RCLONE_CONFIG" copy "$PATH_DB_DUMP/nextcloud_$TIMESTAMP.sql.gz" "$RCLONE_REMOTE/Database"
    
    # Чистка старих файлів (локально)
    find "$PATH_DB_DUMP" -name "*.sql.gz" -mtime +7 -delete
else
    log "ERROR | Помилка дампа бази даних!"
fi

# 2. КОНФІГИ
log "INFO | Бекап конфігів..."
$RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_CONFIGS" "$RCLONE_REMOTE/Configs" \
    --exclude ".git/**" \
    --exclude "nextcloud_data/**" \
    --exclude "db_data/**" \
    --exclude "homepage/cache/**" \
    --exclude "**/.DS_Store" \
    --transfers 4 --log-file "$LOG_FILE" --log-level ERROR

# 3. ДОКУМЕНТИ
log "INFO | Бекап документів..."
if [ -d "$PATH_DOCS" ]; then
    $RCLONE_BIN --config "$RCLONE_CONFIG" sync "$PATH_DOCS" "$RCLONE_REMOTE/Documents" \
        --transfers 4 --log-file "$LOG_FILE" --log-level ERROR
else
    log "WARNING | Папка документів пуста або відсутня."
fi

log "INFO | --- Кінець ---"
