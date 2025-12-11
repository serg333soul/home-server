#!/bin/bash

# --- FIX FOR CRON ---
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- ГЛОБАЛЬНІ НАЛАШТУВАННЯ ---
LOG_FILE="/var/log/file_transfer.log"
NEXTCLOUD_DATA_ROOT="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data/data"
BASE_SSD_PATH="/mnt/ssd_storage"
NOTIFY_SCRIPT="/home/ruban/nextcloud/scripts/notify.sh"

# --- ФУНКЦІЯ ОБРОБКИ ---
process_user_files() {
    local USER_LABEL=$1
    local NC_USER=$2
    local DEST_DIR=$3
    local LINUX_OWNER=$4
    
    local SOURCE_DIR="$NEXTCLOUD_DATA_ROOT/$NC_USER/files/MobileUploads"
    local MOVED_COUNTER=0

    # 1. AUTO-PROVISIONING
    if [ ! -d "$DEST_DIR" ]; then
        local INIT_TIMESTAMP
        INIT_TIMESTAMP=$(date "+%d.%m.%Y %H:%M")
        
        echo "[$INIT_TIMESTAMP] | INIT | Створення нової структури для користувача $NC_USER" >> "$LOG_FILE"
        mkdir -p "$DEST_DIR/Photos"
        mkdir -p "$DEST_DIR/Videos"
        mkdir -p "$DEST_DIR/Documents"
        chown -R www-data:www-data "$DEST_DIR"
        chmod -R 775 "$DEST_DIR"
    fi

    if [ ! -d "$SOURCE_DIR" ] || [ -z "$(ls -A "$SOURCE_DIR")" ]; then
        return
    fi

    for file in "$SOURCE_DIR"/*; do
        if [ -f "$file" ]; then
            FILENAME=$(basename "$file")
            FILESIZE=$(du -h "$file" | cut -f1)
            TIMESTAMP=$(date "+%d.%m.%Y %H:%M")
            
            EXTENSION="${FILENAME##*.}"
            EXTENSION="${EXTENSION,,}"

            case "$EXTENSION" in
                jpg|jpeg|png|heic|gif|bmp|tiff|webp|dng) SUBFOLDER="Photos" ;;
                mp4|mov|avi|mkv|webm|3gp|flv) SUBFOLDER="Videos" ;;
                *) SUBFOLDER="Documents" ;;
            esac

            TARGET_DIR="$DEST_DIR/$SUBFOLDER"
            mkdir -p "$TARGET_DIR"

            if mv "$file" "$TARGET_DIR/" && chown "$LINUX_OWNER:$LINUX_OWNER" "$TARGET_DIR/$FILENAME"; then
                echo "[$TIMESTAMP] | $USER_LABEL | $FILESIZE | $FILENAME" >> "$LOG_FILE"
                ((MOVED_COUNTER++)) 
            else
                MSG="ПОМИЛКА | $USER_LABEL | Не вдалося перемістити $FILENAME"
                echo "[$TIMESTAMP] | $MSG" >> "$LOG_FILE"
                # Термінове сповіщення про помилку
                "$NOTIFY_SCRIPT" "🚨 $MSG" "ERROR"
            fi
        fi
    done

    if [ $MOVED_COUNTER -gt 0 ]; then
        # Оновлення бази
        docker exec -u 33 nextcloud-app-1 php occ files:scan --path="/$NC_USER/files/MobileUploads" > /dev/null 2>&1
        echo "[$TIMESTAMP] | INFO | Базу оновлено ($MOVED_COUNTER файлів) для $USER_LABEL" >> "$LOG_FILE"
        
        # СПОВІЩЕННЯ В ТЕЛЕГРАМ (Тільки якщо були файли)
        "$NOTIFY_SCRIPT" "📂 **Сортування завершено!**%0AКористувач: $USER_LABEL%0AПереміщено файлів: $MOVED_COUNTER" "SUCCESS"
    fi
}

# --- ДИНАМІЧНИЙ ЗАПУСК ---
mapfile -t ALL_NC_USERS < <(docker exec -u 33 nextcloud-app-1 php occ user:list | awk -F: '{print $1}' | sed 's/^[[:space:]-]*//')

for NC_USER in "${ALL_NC_USERS[@]}"; do
    if [[ -z "$NC_USER" ]]; then continue; fi

    case $NC_USER in
        "serg333soul")
            USER_LABEL="Serg"
            TARGET_BASE="$BASE_SSD_PATH/Admin_Files"
            LINUX_OWNER="ruban"
            ;;
        "guest")
            USER_LABEL="Guest"
            TARGET_BASE="$BASE_SSD_PATH/Guest_Files"
            LINUX_OWNER="guest"
            ;;
        *)
            USER_LABEL="${NC_USER^}" 
            TARGET_BASE="$BASE_SSD_PATH/${NC_USER}_Files"
            LINUX_OWNER="www-data"
            ;;
    esac

    process_user_files "$USER_LABEL" "$NC_USER" "$TARGET_BASE" "$LINUX_OWNER"
done
