# PancartPlayer — Ablitération

Outil pour retirer la « direction du refus » d'un modèle GGUF
(machine de travail : **≥ 32 Go de RAM** ou GPU, ou **Colab gratuit**).

## Pipeline

```
GGUF ──>(1) convert_gguf.py──▶ Safetensors fp16
      ──>(2) python -m abliterator ──▶ modèle ablité
      ──>(3) convert_hf_to_gguf.py + llama-quantize ──▶ abliterated-Q4_K_M.gguf
```

## Exécution locale (machine équipée)

```bash
pip install abliterator
git clone https://github.com/ggerganov/llama.cpp  # + build binaire llama-quantize

python3 ablit.py --gguf /chemin/to/model.Q4_K_M.gguf --out-prefix ornith-abliterated
# --dry-run pour prévisualiser sans rien lancer
```

## Colab gratuit (aucun matériel)

1. Ouvrez https://colab.research.google.com
2. Menu ⬆ Upload → sélectionnez `colab_ablit.ipynb`
3. Suivez les cellules (dépôt du GGUF, conversion, ablation, requant, téléchargement).

## Notes honnêtes

- L'ablitération d'un GGUF **déjà quantifié Q4** donne des résultats dégradés ;
  idéal : partir du Safetensors/FP16, ablité, puis chiffrer en Q4_K_M.
- Le modèle `ornith-ai/Ornith-1.5-9B` est un modèle « uncensored » à la base :
  testez-le d'abord avant d'abliter — un modèle déjà décensuré n'en a peut-être pas besoin.
- Résultat personnel : utilisez vos propres modèles, sous votre responsabilité.