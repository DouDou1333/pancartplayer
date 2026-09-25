#!/usr/bin/env bash
# PancartPlayer — signe un APK release avec la clé stable du projet
# (scripts/signing/pancartplayer.jks). Idempotent et réutilisable pour
# le build local ET GitHub Actions, afin que chaque mise à jour
# s'installe par-dessus la précédente (même signature).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_DIR="$ROOT/scripts/signing"
KEY_FILE="$SIGN_DIR/key.properties"
IN="${1:?usage: sign_apk.sh <in.apk> [out.apk]}"
OUT="${2:-${IN%.apk}-signed.apk}"

if [ ! -f "$KEY_FILE" ]; then
  echo "[sign] key.properties introuvable — build non signé" >&2
  cp "$IN" "$OUT"
  exit 0
fi

. "$KEY_FILE"

APKSIGNER_CMD="${APKSIGNER_CMD:-}"
if [ -z "$APKSIGNER_CMD" ]; then
  for d in "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/*/; do
    if [ -x "$d/apksigner" ]; then
      APKSIGNER_CMD="bash $d/apksigner"
      break
    fi
  done
fi
if [ -z "$APKSIGNER_CMD" ]; then
  echo "[sign] apksigner introuvable (ANDROID_HOME=$ANDROID_HOME)" >&2
  cp "$IN" "$OUT"
  exit 0
fi

echo "[sign] signature avec $APKSIGNER_CMD"
# shellcheck disable=SC2086
$APKSIGNER_CMD sign \
  --ks "$SIGN_DIR/$(basename "$storeFile")" \
  --ks-key-alias "$keyAlias" \
  --ks-pass "pass:$keyPassword" \
  --key-pass "pass:$keyPassword" \
  --out "$OUT" "$IN"

echo "[sign] vérification :"
# shellcheck disable=SC2086
$APKSIGNER_CMD verify --print-certs "$OUT" | sed -n '1,2p'