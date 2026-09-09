#!/bin/bash
#
# Script: add_messages.sh
# Fungsi : Untuk setiap user di users.txt:
#          1. Ambil mailboxId via `zmprov gmi`
#          2. Tentukan path folder msg lokal & remote berdasarkan mailboxId
#          3. Rsync file dari remote ke folder msg lokal
#          4. Tambahkan tiap file .msg ke /Inbox via `zmmailbox addMessage`
#
# Jalankan sebagai user zimbra:  su - zimbra -c '/path/to/add_messages.sh'
#

# ==================== KONFIGURASI ====================
USERS_FILE="./users.txt"                 # daftar email, satu per baris
STORE_ROOT="/opt/zimbra/store/0"         # root path store lokal (tujuan rsync)
REMOTE_HOST="root@1.2.3.4"         # host sumber backup
REMOTE_STORE_ROOT="/mnt/recover-vm100/zimbra/store/0"  # root path store di remote (sumber rsync)
TARGET_FOLDER="/Inbox"                   # folder tujuan di mailbox
LOG_DIR="./logs"                         # folder penyimpanan log per user
RUN_TS="$(date +%Y%m%d_%H%M%S)"          # timestamp sekali per eksekusi script

# RSYNC_FLAGS: tanpa -n = rsync BENERAN copy file (bukan simulasi).
# Kalau suatu saat perlu tes/cek dulu tanpa copy file, tambahkan huruf n
# jadi "-avHn" (dry-run), addMessage otomatis ikut di-skip juga.
RSYNC_FLAGS="-avH"
# =======================================================

mkdir -p "$LOG_DIR"

DRY_RUN=false
[[ "$RSYNC_FLAGS" == *n* ]] && DRY_RUN=true

if [ "$DRY_RUN" = true ]; then
    echo "*** MODE DRY-RUN AKTIF: file tidak akan di-copy, addMessage tidak akan dijalankan ***"
fi

if [ ! -f "$USERS_FILE" ]; then
    echo "File $USERS_FILE tidak ditemukan!"
    exit 1
fi

echo "Mulai proses: $(date)"
echo "========================================"

while IFS= read -r USER || [ -n "$USER" ]; do
    # skip baris kosong
    [ -z "$USER" ] && continue

    # sanitize email untuk nama file (ganti @ dan karakter aneh jadi underscore)
    SAFE_USER=$(echo "$USER" | tr -c '[:alnum:].' '_')
    LOG_FILE="$LOG_DIR/${SAFE_USER}_${RUN_TS}.log"

    echo "" | tee -a "$LOG_FILE"
    echo ">>> Memproses user: $USER" | tee -a "$LOG_FILE"

    # 1. Ambil mailboxId
    MAILBOX_ID=$(zmprov gmi "$USER" 2>>"$LOG_FILE" | grep mailboxId | awk '{print $2}')

    if [ -z "$MAILBOX_ID" ]; then
        echo "    [SKIP] Gagal mendapatkan mailboxId untuk $USER" | tee -a "$LOG_FILE"
        continue
    fi

    echo "    mailboxId: $MAILBOX_ID" | tee -a "$LOG_FILE"

    # 2. Tentukan path folder msg (lokal & remote) berdasarkan mailboxId
    MSG_DIR="$STORE_ROOT/$MAILBOX_ID/msg"
    REMOTE_MSG_DIR="$REMOTE_STORE_ROOT/$MAILBOX_ID/msg"

    echo "    Folder msg lokal : $MSG_DIR" | tee -a "$LOG_FILE"
    echo "    Folder msg remote: $REMOTE_HOST:$REMOTE_MSG_DIR" | tee -a "$LOG_FILE"

    mkdir -p "$MSG_DIR"

    # 3. Jalankan rsync dari remote ke folder msg lokal, ambil daftar file .msg
    #    yang berhasil di-transfer dari output rsync (grep '\.msg$')
    echo "    Menjalankan rsync dari $REMOTE_HOST:$REMOTE_MSG_DIR/ ..." | tee -a "$LOG_FILE"

    MSG_LIST=$(rsync $RSYNC_FLAGS --ignore-existing --chown=zimbra:zimbra --progress --stats \
        "$REMOTE_HOST:$REMOTE_MSG_DIR/" "$MSG_DIR/" 2>>"$LOG_FILE" | grep '\.msg$')

    if [ -z "$MSG_LIST" ]; then
        echo "    [SKIP] Tidak ada file .msg baru untuk $USER" | tee -a "$LOG_FILE"
        continue
    fi

    # 4. addMessage satu per satu untuk tiap file .msg hasil rsync
    COUNT=0
    while IFS= read -r REL_PATH; do
        [ -z "$REL_PATH" ] && continue
        MSG_FILE="$MSG_DIR/$REL_PATH"

        if [ "$DRY_RUN" = true ]; then
            echo "    [DRY-RUN] Akan di-add: $MSG_FILE" | tee -a "$LOG_FILE"
            COUNT=$((COUNT+1))
            continue
        fi

        zmmailbox -z -m "$USER" addMessage "$TARGET_FOLDER" "$MSG_FILE" >>"$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            COUNT=$((COUNT+1))
        else
            echo "    [ERROR] Gagal add: $MSG_FILE" | tee -a "$LOG_FILE"
        fi
    done <<< "$MSG_LIST"

    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Total $COUNT pesan yang AKAN di-add untuk $USER (belum benar-benar dijalankan)" | tee -a "$LOG_FILE"
    else
        echo "    Selesai: $COUNT pesan berhasil ditambahkan untuk $USER" | tee -a "$LOG_FILE"
    fi

done < "$USERS_FILE"

echo ""
echo "========================================"
echo "Semua proses selesai: $(date)"
echo "Log per user tersimpan di folder: $LOG_DIR/"
