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
# et iOS >= 16.4 (manifeste Swift Package Manager). flutter create régénère des
# cibles plus basses -> on remonte le déploiement target des projets Runner.
python3 - <<'PY'
import re, pathlib
for xproj in (
    pathlib.Path('macos/Runner.xcodeproj/project.pbxproj'),
    pathlib.Path('ios/Runner.xcodeproj/project.pbxproj'),
):
    if not xproj.exists():
        continue
    src = xproj.read_text()
    patched = re.sub(r'MACOSX_DEPLOYMENT_TARGET\s*=\s*[0-9]+\.[0-9]+;',
                     'MACOSX_DEPLOYMENT_TARGET = 14.0;', src)
    patched = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[0-9]+\.[0-9]+;',
                     'IPHONEOS_DEPLOYMENT_TARGET = 16.4;', patched)
    if patched != src:
        xproj.write_text(patched)
        print(f'[bootstrap] {xproj} -> macos 14.0 / ios 16.4')
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
    patched = re.sub(r'^platform :ios, .*', "platform :ios, '16.4'", src, flags=re.M)
    if patched != src:
        ios_podfile.write_text(patched)
        print('[bootstrap] ios Podfile -> 16.4')
PY

echo "[bootstrap] flutter pub get…"
flutter pub get

# Correctif temporaire : llamadart 0.8.23 déclare le dossier Artifacts/ du
# companion Apple (qui n'existe pas à l'état normal) comme dépendance de hook.
# Flutter tente de l'énumérer -> PathNotFoundException et échec du build Apple.
# Patch du hook installé dans le cache pub : on ne déclare la dépendance que
# si le dossier existe réellement (comportement main, sans le crash).
LLAMADART_HOOK="$HOME/.pub-cache/hosted/pub.dev/llamadart-0.8.23/hook/build.dart"
if [ -f "$LLAMADART_HOOK" ] && grep -q 'output.dependencies.add(artifacts.uri);' "$LLAMADART_HOOK"; then
  python3 - "$LLAMADART_HOOK" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
patched = s.replace(
    "    output.dependencies.add(artifacts.uri);",
    "    if (artifacts.existsSync()) {\n      output.dependencies.add(artifacts.uri);\n    }",
    1,
)
if patched != s:
    open(p, "w").write(patched)
    print("[bootstrap] llamadart hook patched (Artifacts déclaré seulement s'il existe)")
else:
    print("[bootstrap] llamadart hook déjà patché")
PY
fi

echo "[bootstrap] OK — projet prêt dans $APP_DIR"