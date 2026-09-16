#!/usr/bin/env bash
# PancartPlayer — prépare l'environnement Flutter ET génère, si manquant,
# le scaffolding des 6 plateformes (android, ios, linux, macos, windows, web)
# dans app/. Idempotent : ne touche jamais à lib/, pubspec.yaml ni aux sources.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"

if ! command -v flutter >/dev/null 2>&1; then
  echo "[bootstrap] Flutter introuvable — installation dans ~/flutter …"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

cd "$APP_DIR"

if [ ! -f .metadata ]; then
  echo "[bootstrap] Création du scaffolding plateforme…"
  flutter config --no-analytics >/dev/null 2>&1 || true
  flutter create \
    --platforms=android,ios,linux,macos,windows,web \
    --org com.pancart \
    --project-name pancartplayer \
    . || true
  # flutter create génère un widget_test de contre-exemple qui casserait `flutter test`
  rm -f test/widget_test.dart
fi

# macOS : le plugin llama.cpp (llamadart_llama_cpp_flutter) exige macOS >= 14.0.
# flutter create régénère le projet avec une cible 12.0 -> on la remonte.
if [ -f macos/Runner.xcodeproj/project.pbxproj ]; then
  sed -i -E 's/MACOSX_DEPLOYMENT_TARGET[[:space:]]*=[[:space:]]*[0-9]+\.[0-9]+;/MACOSX_DEPLOYMENT_TARGET = 14.0;/g' \
    macos/Runner.xcodeproj/project.pbxproj
fi
if [ -f macos/Podfile ]; then
  sed -i -E "s/^platform :osx, .*/platform :osx, '14.0'/" macos/Podfile
fi

echo "[bootstrap] flutter pub get…"
flutter pub get

echo "[bootstrap] OK — projet prêt dans $APP_DIR"