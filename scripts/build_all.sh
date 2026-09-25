#!/usr/bin/env bash
# PancartPlayer — compile localement TOUTES les plateformes possibles
# et dépose chaque exécutable dans son dossier autonome :
#   launcher/android/  launcher/ios/  launcher/linux/
#   launcher/macos/    launcher/windows/  launcher/web/
# Chaque cible manquante est simplement ignorée.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/bootstrap.sh
cd app

echo ">> Compilation en cours…"

if flutter build apk --release >/dev/null 2>&1; then
  mkdir -p "$ROOT/launcher/android"
  bash "$ROOT/scripts/sign_apk.sh" \
    build/app/outputs/flutter-apk/app-release.apk \
    "$ROOT/launcher/android/pancartplayer.apk" >/dev/null 2>&1
  echo "✓ launcher/android/pancartplayer.apk (signé)"
fi

if flutter build web --release >/dev/null 2>&1; then
  rm -rf "$ROOT/launcher/web"
  mkdir -p "$ROOT/launcher/web"
  cp -r build/web/* "$ROOT/launcher/web/"
  echo "✓ launcher/web/ site statique"
fi

if flutter build linux --release >/dev/null 2>&1; then
  rm -rf "$ROOT/launcher/linux"
  mkdir -p "$ROOT/launcher/linux"
  cp -r build/linux/x64/release/bundle/* "$ROOT/launcher/linux/"
  echo "✓ launcher/linux/ bundle"
fi

if flutter build macos --release >/dev/null 2>&1; then
  rm -rf "$ROOT/launcher/macos"
  mkdir -p "$ROOT/launcher/macos"
  cp -r build/macos/Build/Products/Release/* "$ROOT/launcher/macos/"
  echo "✓ launcher/macos/ app"
fi

if flutter build windows --release >/dev/null 2>&1; then
  rm -rf "$ROOT/launcher/windows"
  mkdir -p "$ROOT/launcher/windows"
  cp -r build/windows/x64/runner/Release/* "$ROOT/launcher/windows/"
  echo "✓ launcher/windows/ exe"
fi

if flutter build ios --no-codesign --release >/dev/null 2>&1; then
  rm -rf "$ROOT/launcher/ios"
  mkdir -p "$ROOT/launcher/ios"
  cp -r build/ios/iphoneos/*.app "$ROOT/launcher/ios/"
  echo "✓ launcher/ios/ app (non signé)"
fi

echo ">> Terminé. Exécutables dans launcher/<plateforme>/."