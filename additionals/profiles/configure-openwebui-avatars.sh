#!/usr/bin/env bash
set -Eeuo pipefail
AVATAR_DIR_LOCAL="/root/homelab-assets/avatars"
AVATAR_DIR_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/avatars"
cat <<MSG
Bu v2.3.10 additionals script iskeletidir.
Avatar arama sırası:
  1) $AVATAR_DIR_LOCAL
  2) $AVATAR_DIR_REPO

Public GitHub repo içine gerçek kişisel fotoğraf koyarsan fotoğraflar public olur.
Bu servis için avatar uygulama connector'ı v2.3.10 sonrası iterasyonda genişletilecek.
MSG
