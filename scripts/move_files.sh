#!/bin/bash

# --- ГЛОБАЛЬНІ НАЛАШТУВАННЯ ---
LOG_FILE="/var/log/file_transfer.log"
NEXTCLOUD_DATA_ROOT="/var/lib/docker/volumes/nextcloud_nextcloud_data/_data/data"
BASE_SSD_PATH="/mnt/ssd_storage"

# --- ФУНКЦІЯ ОБРОБКИ ---
process_user_files() {
    local USER_LABEL=$1
    local NC_USER=$2
    local DEST_DIR=$3
    local LINUX_OWNER=$4
    
    local SOURCE_DIR="$NEXTCLOUD_DATA_ROOT/$NC_USER/files/MobileUploads"
    local MOVED_COUNTER=0

    # 1. AUTO-PROVISIONING (Авто-створення папок)
    # Якщо цільової папки на SSD ще немає - створюємо її!
    if [ ! -d "$DEST_DIR" ]; then
        echo "[$TIMESTAMP] | INIT | Створення нової структури для користувача $NC_USER" >> "$LOG_FILE"
        mkdir -p "$DEST_DIR/Photos"
        mkdir -p "$DEST_DIR/Videos"
        mkdir -p "$DEST_DIR/Documents"
        
        # Надаємо права (www-data щоб Nextcloud мав доступ)
        chown -R www-data:www-data "$DEST_DIR"
        chmod -R 775 "$DEST_DIR"
    fi

    # Якщо папки джерела немає або вона пуста - виходимо
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
            # На всяк випадок перевіряємо підпапку
            mkdir -p "$TARGET_DIR"

            mv "$file" "$TARGET_DIR/"
            
            # Встановлюємо власника
            chown "$LINUX_OWNER:$LINUX_OWNER" "$TARGET_DIR/$FILENAME"
            
            if [ $? -eq 0 ]; then
              echo "[$TIMESTAMP] | $USER_LABEL | $FILESIZE | $FILENAME" >> "$LOG_FILE"
              ((MOVED_COUNTER++)) 
            else
              echo "[$TIMESTAMP] | ПОМИЛКА | $USER_LABEL | Не вдалося перемістити $FILENAME" >> "$LOG_FILE"
            fi
        fi
    done

    # Оновлення бази даних
    if [ $MOVED_COUNTER -gt 0 ]; then
        docker exec -u 33 nextcloud-app-1 php occ files:scan --path="/$NC_USER/files/MobileUploads" > /dev/null 2>&1
        echo "[$TIMESTAMP] | INFO | Базу оновлено ($MOVED_COUNTER файлів) для $USER_LABEL" >> "$LOG_FILE"
    fi
}

# --- ДИНАМІЧНИЙ ЗАПУСК ---

# 1. Отримуємо список ВСІХ користувачів з Nextcloud
# docker exec виконує команду, awk бере першу колонку (логіни), tr прибирає зайве
# Використовуємо mapfile для створення масиву
mapfile -t ALL_NC_USERS < <(docker exec -u 33 nextcloud-app-1 php occ user:list | cut -d: -f1 | tr -d ' ')

# 2. Проходимо по кожному знайденому користувачу
for NC_USER in "${ALL_NC_USERS[@]}"; do
    
    # Ігноруємо системні імена, якщо такі є
    if [[ -z "$NC_USER" ]]; then continue; fi

    # ЛОГІКА ВИЗНАЧЕННЯ ПАПОК (Exceptions vs Standard)
    case $NC_USER in
        "serg333soul")
            # Виключення для Адміна
            USER_LABEL="Serg"
            TARGET_BASE="$BASE_SSD_PATH/Admin_Files"
            LINUX_OWNER="ruban"
            ;;
            
        "guest")
            # Виключення для Гостя
            USER_LABEL="Guest"
            TARGET_BASE="$BASE_SSD_PATH/Guest_Files"
            LINUX_OWNER="guest"
            ;;
            
        *)
            # СТАНДАРТ ДЛЯ ВСІХ НОВИХ (Дружина, Діти, Колеги)
            # Логіка: Перша буква велика, решта як є
            # Наприклад: daryna -> Daryna, папкa -> daryna_Files
            USER_LABEL="${NC_USER^}" 
            TARGET_BASE="$BASE_SSD_PATH/${NC_USER}_Files"
            LINUX_OWNER="www-data" # Стандартний власник для нових юзерів
            ;;
    esac

    # Запускаємо обробку
    process_user_files "$USER_LABEL" "$NC_USER" "$TARGET_BASE" "$LINUX_OWNER"

done
