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

# macOS : le plugin llama.cpp (llamadart_llama_cpp_flutter) exige macOS >= 14.0
# (dans son manifeste Swift Package Manager). flutter create régénère une cible
# 12.0 -> on remonte le déploiement target du projet Runner.
python3 - <<'PY'
import re, pathlib
xproj = pathlib.Path('macos/Runner.xcodeproj/project.pbxproj')
if xproj.exists():
    src = xproj.read_text()
    patched = re.sub(r'MACOSX_DEPLOYMENT_TARGET\s*=\s*[0-9]+\.[0-9]+;',
                     'MACOSX_DEPLOYMENT_TARGET = 14.0;', src)
    patched = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[0-9]+\.[0-9]+;',
                     'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', patched)
    if patched != src:
        xproj.write_text(patched)
        print('[bootstrap] darwin deployment target -> 14.0')
podfile = pathlib.Path('macos/Podfile')
if podfile.exists():
    src = podfile.read_text()
    patched = re.sub(r'^platform :osx, .*', "platform :osx, '14.0'", src, flags=re.M)
    if patched != src:
        podfile.write_text(patched)
        print('[bootstrap] macos Podfile -> 14.0')
ios_podfile = pathlib.Path('ios/Podfile')
if ios_podfile.exists():
    src = ios_podfile.read_text()
    patched = re.sub(r'^platform :ios, .*', "platform :ios, '14.0'", src, flags=re.M)
    if patched != src:
        ios_podfile.write_text(patched)
        print('[bootstrap] ios Podfile -> 14.0')
PY

echo "[bootstrap] flutter pub get…"
flutter pub get

echo "[bootstrap] OK — projet prêt dans $APP_DIR"