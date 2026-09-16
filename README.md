# PancartPlayer

**Plateforme libre : n'importe quel modèle. N'importe quelle IA.**

Un seul lanceur pour :

- **Modèles locaux** — télécharge des GGUF depuis Hugging Face et les exécute
  **sur l'appareil** (llama.cpp via `llamadart`, GPU Vulkan/Metal auto),
  Android, iOS, macOS, Linux, Windows **et navigateur web**.
- **N'importe quelle IA** — connecte-toi à tout service compatible OpenAI
  *OpenAI, OpenRouter, Groq, Ollama (réseau local), vLLM, LM Studio, endpoint custom* :
  URL + clé, stockées chiffrées sur l'appareil.
- **Ablitération intégrée** — génère le pipeline qui retire le refus des
  modèles censurés (localement sur machine équipée ou via Colab gratuit),
  suivi des jobs et import du modèle ablité.

## Structure

```
pancartplayer/
├─ app/                ← Code source Flutter (100 % du produit)
├─ android/            ← APK livré ici (build local ou CI)
├─ ios/                ← App iOS livrée ici (non signée)
├─ linux/              ← Bundle desktop Linux
├─ macos/              ← App macOS
├─ windows/            ← Exécutable Windows
├─ web/                ← Site statique WebAssembly
├─ tools/ablit/        ← Pipeline d'ablitération (local + Colab)
├─ scripts/            ← bootstrap + build multi-plateforme
└─ .github/workflows/  ← CI → remplit les 6 dossiers à chaque push
```

## Démarrage rapide (recommandé : GitHub Actions)

1. Pousse ce dépôt sur GitHub (gratuit).
2. L'action `build` compile les 6 plateformes automatiquement.
3. Récupère les artefacts de chaque job (`Actions` → job → *Artifacts*) :
   - `android-apk` → `android/pancartplayer.apk`
   - `web` → site à héberger n'importe où
   - `linux` / `macos` / `ios` / `windows` → exécutables respectifs

## Compilation locale

```bash
bash scripts/bootstrap.sh     # installe Flutter + génère le scaffolding
bash scripts/build_all.sh     # compile les cibles possibles → dans leur dossier
```

Notes honnêtes :

- **iOS nécessite macOS** (Xcode) et un compte Apple pour installer sur
  appareil. La CI produit un `.app` non signé (sideload).
- **Android** : APK arm64/v7a/x86_64 universel.
- Les modèles, eux, restent **interopérables partout** : un GGUF téléchargé
  sur Android est importable sur Linux, etc.

## Utilisation

1. Onglet **IA** → ajoute un fournisseur cloud (presets rapides disponibles).
2. Onglet **Modèles** → télécharge un GGUF adapté à ta RAM
   (`phone` ≤ ~1,2 Go, `all` ~2-3 Go ; au-delà → cloud).
3. Onglet **Chat** → nouvelle conversation : choisis **Local** (sur l'appareil)
   ou **Cloud** (API distante), puis le modèle. Un badge affiche le moteur actif
   (`⚙ Local · qwen3-4b` ou `☁ Cloud · llama-3.3-70b`) et permet de **basculer
   local ↔ cloud** sans perdre l'historique. Les modèles > 3 Go sont refusés en
   local sur un téléphone : bascule en cloud.
4. Onglet **Ablitération** → génère le script, exécute-le sur un PC
   costaud ou copie le notebook Colab (gratuit), puis importe le résultat.

## Ablitération (`tools/ablit/`)

```bash
pip install abliterator
python3 tools/ablit/ablit.py --gguf /chemin/mon-modele-Q4_K_M.gguf
# ou, sur Colab : ouvrir tools/ablit/colab_ablit.ipynb
```

Voir `tools/ablit/README.md`.

## Sémantique de version

- **v0.1.0** — MVP : chat local/cloud avec badge moteur, catalogue HF,
  téléchargement progressif, fournisseurs OpenAI-compatibles, garde-fou RAM
  (modèles lourds → cloud), assistant d'ablitération.
- **v1.1** — thème clair, import de modèles custom par URL, paramètres
  avancés, export/import des conversations.

## Licence

MIT — voir [LICENSE](LICENSE). Tu utilises tes propres modèles, sous ta
responsabilité.