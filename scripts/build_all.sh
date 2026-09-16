#!/usr/bin/env bash
# PancartPlayer — compile localement TOUTES les plateformes possibles
# et dépose chaque exécutable dans son dossier respectif :
#   android/  ios/  linux/  macos/  windows/  web/
# Chaque cible manquante est simplement ignorée.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/bootstrap.sh
cd app

echo ">> Compilation en cours…"

if flutter build apk --release >/dev/null 2>&1; then
  mkdir -p "$ROOT/android"
  cp build/app/outputs/flutter-apk/app-release.apk "$ROOT/android/pancartplayer.apk"
  echo "✓ android/pancartplayer.apk"
fi

if flutter build web --release >/dev/null 2>&1; then
  rm -rf "$ROOT/web"
  mkdir -p "$ROOT/web"
  cp -r build/web/* "$ROOT/web/"
  echo "✓ web/ site statique"
fi

if flutter build linux --release >/dev/null 2>&1; then
  rm -rf "$ROOT/linux"
  mkdir -p "$ROOT/linux"
  cp -r build/linux/x64/release/bundle/* "$ROOT/linux/"
  echo "✓ linux/ bundle"
fi

if flutter build macos --no-codesign --release >/dev/null 2>&1; then
  rm -rf "$ROOT/macos"
  mkdir -p "$ROOT/macos"
  cp -r build/macos/Build/Products/Release/* "$ROOT/macos/"
  echo "✓ macos/ app"
fi

if flutter build windows --release >/dev/null 2>&1; then
  rm -rf "$ROOT/windows"
  mkdir -p "$ROOT/windows"
  cp -r build/windows/x64/runner/Release/* "$ROOT/windows/"
  echo "✓ windows/ exe"
fi

if flutter build ios --no-codesign --release >/dev/null 2>&1; then
  rm -rf "$ROOT/ios"
  mkdir -p "$ROOT/ios"
  cp -r build/ios/iphoneos/*.app "$ROOT/ios/"
  echo "✓ ios/ app (non signé)"
fi

echo ">> Terminé. Exécutables dans les dossiers respectifs."