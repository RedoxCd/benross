#!/usr/bin/env bash
# Vaultwarden backup — snippet to append to /home/ubuntu/backup.sh
# (kept standalone here since backup.sh isn't in this repo; copy the
# function below into it, or `source` this file from it)

set -euo pipefail

VAULTWARDEN_CONTAINER="vaultwarden"
VAULTWARDEN_DATA="/home/ubuntu/vaultwarden/data"
VAULTWARDEN_BACKUP_DIR="/home/ubuntu/backups/vaultwarden"
VAULTWARDEN_RETENTION_DAYS=14

backup_vaultwarden() {
    local date_stamp
    date_stamp="$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$VAULTWARDEN_BACKUP_DIR"

    # 1. Consistent SQLite snapshot via the .backup command (safe on a live DB,
    #    no need to stop the container).
    docker exec "$VAULTWARDEN_CONTAINER" sh -c \
        "sqlite3 /data/db.sqlite3 '.backup \"/data/db_backup_tmp.sqlite3\"'"
    docker cp "$VAULTWARDEN_CONTAINER:/data/db_backup_tmp.sqlite3" \
        "$VAULTWARDEN_BACKUP_DIR/db_${date_stamp}.sqlite3"
    docker exec "$VAULTWARDEN_CONTAINER" rm -f /data/db_backup_tmp.sqlite3

    # 2. Full data dir (attachments, sends, RSA keys, config.json, icon cache...)
    #    excluding the live WAL/SHM files, since the sqlite snapshot above
    #    already gives us a consistent DB copy.
    tar czf "$VAULTWARDEN_BACKUP_DIR/vaultwarden_full_${date_stamp}.tar.gz" \
        -C "$VAULTWARDEN_DATA" \
        --exclude='db.sqlite3-wal' \
        --exclude='db.sqlite3-shm' \
        .

    # 3. Retention: drop backups older than N days
    find "$VAULTWARDEN_BACKUP_DIR" -type f -mtime "+${VAULTWARDEN_RETENTION_DAYS}" -delete
}

backup_vaultwarden
