#!/usr/bin/env bash
# PancartPlayer — récupère les artefacts du dernier build CI réussi et les
# range en dossiers AUTONOMES par plateforme :
#   launcher/android/  launcher/windows/  launcher/linux/
#   launcher/macos/    launcher/ios/      launcher/web/
#
# Un dossier « launcher/<plateforme>/ » se copie/partage tel quel et
# l'exécutable fonctionne (ses dépendances voyagent avec lui) ; les
# plateformes ne dépendent pas les unes des autres. Les archives .zip
# par plateforme seront ajoutées une fois le développement complet.
#
# Usage :
#   scripts/fetch_and_group.sh [DEST] [RUN_ID]
#
#   DEST    dossier de livraison (défaut : Download/PancartPlayer)
#   RUN_ID  run GitHub Actions (défaut : dernier run « build » réussi)
set -euo pipefail

DEST="${1:-/storage/emulated/0/Download/PancartPlayer}"
RUN="${2:-$(gh run list --workflow build.yml --status success --limit 1 \
  --json databaseId -q '.[0].databaseId')}"

if [ -z "$RUN" ]; then
  echo "Aucun run « build » réussi trouvé. Pousse d'abord sur main." >&2
  exit 1
fi

LAUNCHER="$DEST/launcher"
mkdir -p "$LAUNCHER"
echo ">> Run $RUN -> $LAUNCHER"

declare -A MAP=(
  [android-apk]=android
  [windows]=windows
  [linux]=linux
  [macos]=macos
  [ios]=ios
  [web]=web
)

for artifact in android-apk windows linux macos ios web; do
  platform="${MAP[$artifact]}"
  target="$LAUNCHER/$platform"
  echo ">> $artifact -> launcher/$platform"
  rm -rf "$target"
  mkdir -p "$target"
  gh run download "$RUN" -n "$artifact" -D "$target"
done

echo ">> Terminé. Dossiers autonomes :"
ls -1 "$LAUNCHER"
