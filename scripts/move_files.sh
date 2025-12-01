#!/bin/bash

# --- ГЛОБАЛЬНІ НАЛАШТУВАННЯ ---
LOG_FILE="/var/log/file_transfer.log"
NEXTCLOUD_DATA_ROOT="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data/data"

# Створення лог-файлу, якщо немає
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
fi

# --- ФУНКЦІЯ ОБРОБКИ ---
process_user_files() {
local USER_LABEL=$1
    local NC_USER=$2
    local DEST_DIR=$3
    local LINUX_OWNER=$4
    
    local SOURCE_DIR="$NEXTCLOUD_DATA_ROOT/$NC_USER/files/MobileUploads"
    local MOVED_COUNTER=0  # Лічильник переміщених файлів

    if [ ! -d "$SOURCE_DIR" ] || [ -z "$(ls -A "$SOURCE_DIR")" ]; then
        return
    fi

    for file in "$SOURCE_DIR"/*; do
        if [ -f "$file" ]; then
            FILENAME=$(basename "$file")
            FILESIZE=$(du -h "$file" | cut -f1)
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            
            EXTENSION="${FILENAME##*.}"
            EXTENSION="${EXTENSION,,}"

            case "$EXTENSION" in
                jpg|jpeg|png|heic|gif|bmp|tiff|webp|dng) SUBFOLDER="Photos" ;;
                mp4|mov|avi|mkv|webm|3gp|flv) SUBFOLDER="Videos" ;;
                *) SUBFOLDER="Documents" ;;
            esac

            TARGET_DIR="$DEST_DIR/$SUBFOLDER"
            mkdir -p "$TARGET_DIR"

            mv "$file" "$TARGET_DIR/"
            chown "$LINUX_OWNER:$LINUX_OWNER" "$TARGET_DIR/$FILENAME"
            
            if [ $? -eq 0 ]; then
                echo "$TIMESTAMP | $USER_LABEL | $SUBFOLDER | $FILENAME -> OK" >> "$LOG_FILE"
                ((MOVED_COUNTER++)) # Рахуємо успішні переміщення
            else
                echo "$TIMESTAMP | ПОМИЛКА: $FILENAME" >> "$LOG_FILE"
            fi
        fi
    done

    # --- НОВИЙ БЛОК: ОНОВЛЕННЯ БАЗИ ДАНИХ ---
    # Запускаємо сканування ТІЛЬКИ якщо хоч один файл був переміщений
    if [ $MOVED_COUNTER -gt 0 ]; then
        # УВАГА: Замініть 'nextcloud-app-1' на реальне ім'я вашого контейнера з 'docker ps'
        docker exec -u 33 nextcloud-app-1 php occ files:scan --path="/$NC_USER/files/MobileUploads" > /dev/null 2>&1
        echo "$(date "+%Y-%m-%d %H:%M:%S") | INFO | Базу Nextcloud оновлено для $USER_LABEL" >> "$LOG_FILE"
    fi
}

# --- ЗАПУСК ДЛЯ КОРИСТУВАЧІВ ---

# 1. АДМІН (Serg)
# Nextcloud User: serg333soul
# Linux User: ruban (який керує сервером)
# Папка на SSD: Admin_Files
process_user_files "Serg" "serg333soul" "/mnt/ssd_storage/Admin_Files" "ruban"

# 2. ГІСТЬ
# Nextcloud User: guest
# Linux User: guest
# Папка на SSD: Guest_Files
process_user_files "Guest" "guest" "/mnt/ssd_storage/Guest_Files" "guest"
