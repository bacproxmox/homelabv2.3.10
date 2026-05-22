#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/utils/env-loader.sh"
source "$REPO_ROOT/utils/logging.sh"
source "$REPO_ROOT/utils/remote.sh"
source "$REPO_ROOT/utils/state.sh"
source "$REPO_ROOT/utils/env-write.sh"
start_log "chia-farmer-install"
load_all_env

CHIA_ENV="$SECRETS_DIR/chia.env"
ask_text_default(){ local var="$1" prompt="$2" def="$3" value=""; read -r -p "$prompt [$def]: " value; printf -v "$var" "%s" "${value:-$def}"; }
ask_mnemonic_hidden(){
  local a=""
  while true; do
    read -r -s -p "Chia 24-word mnemonic (gizli input, ekranda/logda görünmez): " a; echo
    a="$(echo "$a" | xargs)"
    local wc; wc="$(awk '{print NF}' <<<"$a")"
    if [[ -z "$a" ]]; then echo "❌ Mnemonic boş olamaz."; continue; fi
    if [[ "$wc" -ne 24 ]]; then echo "❌ Mnemonic $wc kelime görünüyor; 24 kelime olmalı."; continue; fi
    echo "✅ Mnemonic alındı, 24 kelime doğrulandı. İçerik loga basılmadı."
    CHIA_MNEMONIC="$a"
    break
  done
}

if [[ ! -f "$CHIA_ENV" ]]; then
  echo "🌱 Chia farmer için geçici secret dosyası oluşturulacak. Script sonunda shred ile silinecek."
  ask_mnemonic_hidden
  echo
  echo "📦 Chia mainnet DB bootstrap yöntemi:"
  echo "  1) Fresh sync / DB atla"
  echo "  2) HTTP/HTTPS URL'den DB indir"
  echo "  3) Torrent/magnet URL ile indir (aria2c)"
  echo "  4) VM107 üzerinde mevcut dosya path'i kullan"
  read -r -p "Seçim [1]: " CHIA_DB_MODE
  CHIA_DB_MODE="${CHIA_DB_MODE:-1}"
  CHIA_DB_DOWNLOAD_URL=""
  CHIA_DB_MANUAL_PATH=""
  case "$CHIA_DB_MODE" in
    2) ask_text_default CHIA_DB_DOWNLOAD_URL "Chia DB HTTP/HTTPS URL" "" ; CHIA_DB_MODE="url" ;;
    3) ask_text_default CHIA_DB_DOWNLOAD_URL "Chia DB torrent/magnet URL" "" ; CHIA_DB_MODE="torrent" ;;
    4) ask_text_default CHIA_DB_MANUAL_PATH "VM107 üzerindeki DB dosyası path'i" "/tmp/blockchain_v2_mainnet.sqlite" ; CHIA_DB_MODE="manual" ;;
    *) CHIA_DB_MODE="fresh" ;;
  esac
  {
    write_env_header
    write_env_line CHIA_MNEMONIC "$CHIA_MNEMONIC"
    write_env_line CHIA_DB_MODE "$CHIA_DB_MODE"
    write_env_line CHIA_DB_DOWNLOAD_URL "$CHIA_DB_DOWNLOAD_URL"
    write_env_line CHIA_DB_MANUAL_PATH "$CHIA_DB_MANUAL_PATH"
  } > "$CHIA_ENV"
  chmod 600 "$CHIA_ENV"
fi

# shellcheck disable=SC1090
source "$CHIA_ENV"

wait_ssh 107
TMP_REMOTE="/tmp/homelab-chia-install.sh"
MNEMONIC_REMOTE="/tmp/chia-mnemonic.txt"

printf '%s
' "$CHIA_MNEMONIC" > /tmp/chia-mnemonic.txt
chmod 600 /tmp/chia-mnemonic.txt
scp "${SSH_OPTS[@]}" /tmp/chia-mnemonic.txt "$SSH_USER@192.168.50.107:$MNEMONIC_REMOTE" >/dev/null
shred -u /tmp/chia-mnemonic.txt || rm -f /tmp/chia-mnemonic.txt

cat > /tmp/homelab-chia-install.sh <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
CHIA_HOME="/home/bacmaster/.chia/mainnet"
CHIA_SRC="/opt/chia-blockchain"
MNEMONIC_FILE="/tmp/chia-mnemonic.txt"
DB_MODE="${CHIA_DB_MODE:-fresh}"
DB_URL="${CHIA_DB_DOWNLOAD_URL:-}"
DB_MANUAL_PATH="${CHIA_DB_MANUAL_PATH:-}"
DB_TARGET="$CHIA_HOME/db/blockchain_v2_mainnet.sqlite"

sudo apt update
sudo apt install -y git curl ca-certificates build-essential python3 python3-venv python3-pip python3-dev lsb-release jq tmux unzip rsync aria2 gzip

if [[ ! -d "$CHIA_SRC/.git" ]]; then
  sudo git clone https://github.com/Chia-Network/chia-blockchain.git -b latest --recurse-submodules "$CHIA_SRC"
else
  cd "$CHIA_SRC"
  sudo git fetch --all --tags
  sudo git checkout latest || true
  sudo git pull --recurse-submodules || true
  sudo git submodule update --init --recursive
fi

sudo chown -R bacmaster:bacmaster "$CHIA_SRC"
cd "$CHIA_SRC"
sudo -u bacmaster bash -lc 'sh install.sh'
sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia init'

if [[ -s "$MNEMONIC_FILE" ]]; then
  echo "🔐 Chia mnemonic import ediliyor (içerik loga basılmaz)..."
  sudo -u bacmaster bash -lc "cd /opt/chia-blockchain && . ./activate && chia keys add -f '$MNEMONIC_FILE' || true"
  shred -u "$MNEMONIC_FILE" || sudo rm -f "$MNEMONIC_FILE"
fi

bootstrap_db(){
  sudo -u bacmaster mkdir -p "$CHIA_HOME/db"
  local src="$1"
  case "$src" in
    *.gz) gzip -dc "$src" > "$DB_TARGET" ;;
    *.zip) tmpd="/tmp/chia-db-unzip"; rm -rf "$tmpd"; mkdir -p "$tmpd"; unzip -o "$src" -d "$tmpd" >/dev/null; found="$(find "$tmpd" -type f -name 'blockchain_v2_mainnet.sqlite*' | head -n1)"; [[ -n "$found" ]] || { echo "❌ zip içinde DB bulunamadı"; return 1; }; cp "$found" "$DB_TARGET" ;;
    *) cp "$src" "$DB_TARGET" ;;
  esac
  sudo chown -R bacmaster:bacmaster "$CHIA_HOME"
  echo "✅ Chia DB hazır: $DB_TARGET"
}

case "$DB_MODE" in
  url)
    if [[ -n "$DB_URL" ]]; then
      echo "📦 Chia DB HTTP/HTTPS URL'den indiriliyor..."
      tmp="/tmp/chia-db-download"
      curl -fL "$DB_URL" -o "$tmp"
      bootstrap_db "$tmp"
      rm -f "$tmp"
    else
      echo "⚠️ DB URL boş; fresh sync ile devam."
    fi
    ;;
  torrent)
    if [[ -n "$DB_URL" ]]; then
      echo "📦 Chia DB torrent/magnet ile indiriliyor..."
      mkdir -p /tmp/chia-db-torrent
      aria2c --seed-time=0 --dir=/tmp/chia-db-torrent "$DB_URL" || true
      found="$(find /tmp/chia-db-torrent -type f \( -name '*.sqlite' -o -name '*.sqlite.gz' -o -name '*.zip' \) | head -n1)"
      [[ -n "$found" ]] && bootstrap_db "$found" || echo "⚠️ Torrent indirildi ama DB dosyası bulunamadı; fresh sync ile devam."
    else
      echo "⚠️ Torrent URL boş; fresh sync ile devam."
    fi
    ;;
  manual)
    if [[ -n "$DB_MANUAL_PATH" && -f "$DB_MANUAL_PATH" ]]; then
      echo "📦 Manuel DB dosyası kullanılıyor: $DB_MANUAL_PATH"
      bootstrap_db "$DB_MANUAL_PATH"
    else
      echo "⚠️ Manuel DB path bulunamadı: ${DB_MANUAL_PATH:-empty}; fresh sync ile devam."
    fi
    ;;
  *)
    echo "ℹ️ Fresh sync seçildi; DB bootstrap atlandı."
    ;;
esac

sudo tee /etc/systemd/system/chia-farmer.service >/dev/null <<'UNIT'
[Unit]
Description=Chia Farmer
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=bacmaster
WorkingDirectory=/opt/chia-blockchain
Environment=CHIA_ROOT=/home/bacmaster/.chia/mainnet
ExecStart=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia start farmer -r'
ExecStop=/bin/bash -lc 'cd /opt/chia-blockchain && . ./activate && chia stop all -d'
Restart=on-failure
RestartSec=20
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

sudo ln -sf /opt/chia-blockchain/venv/bin/chia /usr/local/bin/chia || true
sudo systemctl daemon-reload
sudo systemctl enable chia-farmer.service
sudo systemctl restart chia-farmer.service || true
sudo -u bacmaster bash -lc 'cd /opt/chia-blockchain && . ./activate && chia show -s || true'
REMOTE

scp "${SSH_OPTS[@]}" /tmp/homelab-chia-install.sh "$SSH_USER@192.168.50.107:$TMP_REMOTE" >/dev/null
{
  printf 'CHIA_DB_MODE=%q\n' "${CHIA_DB_MODE:-fresh}"
  printf 'CHIA_DB_DOWNLOAD_URL=%q\n' "${CHIA_DB_DOWNLOAD_URL:-}"
  printf 'CHIA_DB_MANUAL_PATH=%q\n' "${CHIA_DB_MANUAL_PATH:-}"
} > /tmp/chia-remote.env
scp "${SSH_OPTS[@]}" /tmp/chia-remote.env "$SSH_USER@192.168.50.107:/tmp/chia-remote.env" >/dev/null
rm -f /tmp/chia-remote.env
ssh "${SSH_OPTS[@]}" "$SSH_USER@192.168.50.107" "chmod +x $TMP_REMOTE && sudo bash -c 'set -a; source /tmp/chia-remote.env; set +a; $TMP_REMOTE; rm -f /tmp/chia-remote.env'"
rm -f /tmp/homelab-chia-install.sh

if [[ -f "$CHIA_ENV" ]]; then
  echo "🧹 Chia secret dosyası siliniyor: $CHIA_ENV"
  shred -u "$CHIA_ENV" || rm -f "$CHIA_ENV"
fi

echo "🔧 Chia plot disk / compressed plot repair uygulanıyor..."
bash "$REPO_ROOT/maintenance/repair/repair-chia-plot-disks.sh" || echo "⚠️ Chia plot disk repair tamamlanamadı; maintenance menüsünden tekrar çalıştırabilirsin."

state_set chia_farmer_installed true
state_set chia_farmer_installed_at "$(date -Is)"
echo "✅ Chia farmer kurulumu tamamlandı."
