/// Service d'ablitération — prépare, guide et suit les jobs.
///
/// L'ablitération s'exécute sur une machine capable (>= 32 Go de RAM) ou
/// dans Colab. L'application génère les commandes exactes, monitore le job
/// et permet d'importer le GGUF ablité dans le catalogue.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'models.dart';

class AblitService {
  AblitService._();
  static final AblitService instance = AblitService._();

  /// Vérifie si l'exécution locale est techniquement possible.
  bool get canRunLocally {
    if (kIsWeb) return false;
    final p = defaultTargetPlatform;
    return p == TargetPlatform.linux ||
        p == TargetPlatform.macOS ||
        p == TargetPlatform.windows;
  }

  /// Génère le script bash complet de la pipeline locale.
  /// `ggufPath` : chemin du GGUF source (ex: ornith-9b-Q4_K_M.gguf).
  static String buildLocalScript(String ggufPath) {
    final out = 'abliterated_${DateTime.now().millisecondsSinceEpoch}';
    return '''
#!/usr/bin/env bash
# PancartPlayer — Pipeline d'ablitération (AGENTS: machine >= 32 Go RAM ou GPU)
set -euo pipefail

SRC="${ggufPath}"
OUT="${out}"
WORK="work_${out}"
mkdir -p "\$WORK"

echo "[1/4] Conversion GGUF -> Safetensors (fp16)…"
python3 "\${LLAMA_CPP}/tools/convert_gguf.py" "\$SRC" --outtype f32 --outfile "\$WORK/model_fp16" \
  || python3 "\${LLAMA_CPP}/tools/gguf/convert_gguf.py" "\$SRC" --outfile "\$WORK" 

echo "[2/4] Ablitération (ABliterator)…"
python3 -m abliterator --model "\$WORK" --output "\$WORK/abliterated"

echo "[3/4] Re-quantification Q4_K_M…"
python3 "\${LLAMA_CPP}/convert_hf_to_gguf.py" "\$WORK/abliterated" --outfile "\$OUT.f16.gguf"
"\${LLAMA_CPP}/llama-quantize" "\$OUT.f16.gguf" "\$OUT-Q4_K_M.gguf" Q4_K_M

echo "[4/4] Terminé : \$OUT-Q4_K_M.gguf"
echo "Importez ce fichier dans PancartPlayer pour l'utiliser."
''';
  }

  /// Le texte du notebook Colab (marche partout, gratuit).
  static String buildColabMarkdown() {
    return '''
# PancartPlayer — Ablitération dans Colab (gratuit)

1. Allez sur https://colab.research.google.com, « Bloc-notes + nouveau ».
2. Téléversez votre GGUF par l'icône 📁 (ou montez Google Drive).
3. Collez ce code dans une cellule :

```
!git clone https://github.com/ggerganov/llama.cpp
%cd llama.cpp
!python3 -m pip install abliterator
!python3 tools/convert_gguf.py "/content/<VOTRE_FICHIER>.gguf" --outfile /content/model
!python3 -m abliterator --model /content/model --output /content/model_ablit
!python3 convert_hf_to_gguf.py /content/model_ablit --outfile /content/ablit.f16.gguf
!./build/bin/llama-quantize /content/ablit.f16.gguf /content/ablit-Q4_K_M.gguf Q4_K_M
```

> À adapter selon votre GGUF et la version de llama.cpp.
> Téléchargez ensuite `ablit-Q4_K_M.gguf` depuis l'onglet Fichiers.
''';
  }

  /// Enregistre un job de suivi dans l'application.
  Future<AblitJob> createJob(AppStoreLike store, String sourceName) async {
    final job = AblitJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}',
      sourceModelName: sourceName,
      createdAt: DateTime.now(),
    );
    await store.saveJob(job);
    return job;
  }

  /// Lancement local (optionnel, plateformes desktop). Retourne un flux
  /// de logs encodés — `null` si la plateforme ne permet pas l'exécution.
  Stream<String> runLocally({
    required String ggufPath,
    required AblitJob job,
    required Future<void> Function(AblitJob) onSave,
  }) async* {
    if (!canRunLocally) {
      yield 'Exécution locale impossible (RAM insuffisante / plateforme mobile). Utilisez le notebook Colab.';
      return;
    }
    await onSave(job.copyWith(state: AblitState.running, step: 'Préparation'));

    final script = buildLocalScript(ggufPath);
    yield script;

    yield '\n[Environnement requis] llama.cpp + abliterator + >= 32 Go de RAM.';
    await onSave(job.copyWith(
      state: AblitState.done,
      step: 'Script généré — exécutez-le dans votre shell.',
    ));
  }
}

/// Interface minimale pour éviter une dépendance circulaire avec la store.
abstract class AppStoreLike {
  Future<void> saveJob(AblitJob j);
}