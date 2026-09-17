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

# macOS : support de macOS 12. Le commentaire SwiftPM du plugin a été retiré du
# pubspec (llamadart utilise ses binaires macOS natifs en fallback, qui exigent
# 13.3 au moment du chargement -> erreur gérée dans l'app). macOS peut donc
# rester en 12.0. iOS garde 16.4 (exigence llamadart).
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
                     'MACOSX_DEPLOYMENT_TARGET = 12.0;', src)
    patched = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[0-9]+\.[0-9]+;',
                     'IPHONEOS_DEPLOYMENT_TARGET = 16.4;', patched)
    if patched != src:
        xproj.write_text(patched)
        print(f'[bootstrap] {xproj} -> macos 12.0 / ios 16.4')
podfile = pathlib.Path('macos/Podfile')
if podfile.exists():
    src = podfile.read_text()
    patched = re.sub(r'^platform :osx, .*', "platform :osx, '12.0'", src, flags=re.M)
    if patched != src:
        podfile.write_text(patched)
        print('[bootstrap] macos Podfile -> 12.0')
ios_podfile = pathlib.Path('ios/Podfile')
if ios_podfile.exists():
    src = ios_podfile.read_text()
    patched = re.sub(r'^platform :ios, .*', "platform :ios, '16.4'", src, flags=re.M)
    if patched != src:
        ios_podfile.write_text(patched)
        print('[bootstrap] ios Podfile -> 16.4')
PY

# macOS : le template Flutter active le sandbox SANS com.apple.security.network.client
# -> toute connexion sortante (API distantes, Ollama sur localhost:11434) échoue en
# « SocketException: Operation not permitted (errno=1) ». On ajoute l'autorisation
# réseau client aux deux entitlements (DebugProfile + Release). Idempotent.
python3 - <<'PY'
import pathlib

def ensure(rel: str, keys_and_bools: list[tuple[str, bool]]):
    p = pathlib.Path(rel)
    text = p.read_text() if p.exists() else ''
    additions = ''
    for key, val in keys_and_bools:
        if key not in text:
            additions += (f'\t<key>{key}</key>\n\t<{"true" if val else "false"}/>\n')
    if not additions:
        print(f'[bootstrap] {rel} : entitlements déjà à jour')
        return
    if 'dict>' not in text:
        text = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0">\n<dict>\n</dict>\n</plist>\n')
    head, tail = text.split('</dict>', 1)
    p.write_text(head + additions + '</dict>' + tail)
    print(f'[bootstrap] {rel} : + entitlements réseau/fichiers (sandbox macOS)')

ensure('macos/Runner/DebugProfile.entitlements', [
    ('com.apple.security.app-sandbox', True),
    ('com.apple.security.cs.allow-jit', True),
    ('com.apple.security.network.server', True),
    ('com.apple.security.network.client', True),
    ('com.apple.security.files.user-selected.read-only', True),
])
ensure('macos/Runner/Release.entitlements', [
    ('com.apple.security.app-sandbox', True),
    ('com.apple.security.network.client', True),
    ('com.apple.security.files.user-selected.read-only', True),
])
PY

# Android : le template Flutter ne déclare android.permission.INTERNET que dans
# les manifests debug/profile. En release, l'APK généré n'a alors AUCUN droit
# réseau -> connect() échoue en « SocketException: Operation not permitted,
# errno=1 ». On garantit la permission dans le manifest principal (idempotent).
python3 - <<'PY'
import pathlib, re
MANIFEST = pathlib.Path('android/app/src/main/AndroidManifest.xml')
if not MANIFEST.exists():
    print('[bootstrap] manifest Android absent (plateforme non générée — ignoré)')
else:
    src = MANIFEST.read_text()
    added = []
    if 'android.permission.INTERNET' not in src:
        added.append('INTERNET')
    if 'usesCleartextTraffic' not in src:
        added.append('usesCleartextTraffic')
    if 'android.permission.INTERNET' not in src:
        src = src.replace(
            '<application',
            '<uses-permission android:name="android.permission.INTERNET" />\n    <application',
            1)
    if 'usesCleartextTraffic' not in src:
        src = re.sub(
            r'(<application\b[^>]*?)(\s*/?>)',
            lambda mo: mo.group(1) + ' android:usesCleartextTraffic="true"' + mo.group(2),
            src, count=1)
    if added:
        MANIFEST.write_text(src)
        print('[bootstrap] android main manifest : + ' + ', '.join(added))
    else:
        print('[bootstrap] android main manifest : déjà à jour')
PY

# iOS : NSLocalNetworkUsageDescription (permission « réseau local » depuis
# iOS 14) + exception ATS « local networking » pour autoriser le http:// LAN
# (ex: joindre un Ollama sur le PC depuis l'iPhone/iPad). Idempotent.
python3 - <<'PY'
import pathlib
plist = pathlib.Path('ios/Runner/Info.plist')
if not plist.exists():
    print('[bootstrap] ios Info.plist absent (plateforme non générée — ignoré)')
else:
    s = plist.read_text()
    added = []
    if 'NSLocalNetworkUsageDescription' not in s and '</dict>' in s:
        s = s.replace(
            '</dict>',
            '\t<key>NSLocalNetworkUsageDescription</key>\n'
            '\t<string>Connexion aux serveurs d\'IA de votre réseau local (ex: Ollama).</string>\n'
            '</dict>', 1)
        added.append('NSLocalNetworkUsageDescription')
    if 'NSAppTransportSecurity' not in s and '</dict>' in s:
        s = s.replace(
            '</dict>',
            '\t<key>NSAppTransportSecurity</key>\n'
            '\t<dict>\n'
            '\t\t<key>NSAllowsLocalNetworking</key>\n'
            '\t\t<true/>\n'
            '\t</dict>\n'
            '</dict>', 1)
        added.append('ATS local networking')
    if added:
        plist.write_text(s)
        print('[bootstrap] ios Info.plist : + ' + ', '.join(added))
    else:
        print('[bootstrap] ios Info.plist : déjà à jour')
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