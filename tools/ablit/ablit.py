#!/usr/bin/env python3
"""
PancartPlayer — Ablitération d'un GGUF.

Pipeline complet et reproductible :
  1. GGUF -> Safetensors (fp16)        (llama.cpp convert_gguf.py)
  2. Ablitération (retrait du refus)   (FailSpy/ABliterator)
  3. Re-quantification Q4_K_M          (llama.cpp convert_hf_to_gguf.py + llama-quantize)

Prérequis machine : >= 32 Go de RAM (ou un GPU ~20 Go), python 3.10+,
git, cmake, et un build de llama.cpp (binaire `llama-quantize`).

Usage :
    python3 ablit.py --gguf /chemin/mon-modele.Q4_K_M.gguf [--out-prefix abliterated]

Options :
    --dry-run          Affiche la pipeline sans rien exécuter.
    --keep-fp16        Ne supprime pas l'intermédiaire fp16.
    --no-pip           N'installe pas abliterator automatiquement.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

MIN_RAM_MB = 28_000
LLAMA_CPP_GIT = "https://github.com/ggerganov/llama.cpp.git"


def log(step: str, msg: str) -> None:
    print(f"\n[{step}] {msg}", flush=True)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    print("    $", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def ram_mb() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return 0


def check_environment() -> None:
    log("ENV", "Vérification de l'environnement")
    total = ram_mb()
    if sys.platform.startswith("linux") and total and total < MIN_RAM_MB:
        sys.exit(
            f"RAM insuffisante : {total} Mo détectés, il faut ≥ {MIN_RAM_MB} Mo.\n"
            "Utilisez tools/ablit/colab_ablit.ipynb (Colab gratuit, T4 16 Go) "
            "ou une machine/VM plus costaude."
        )
    if sys.version_info < (3, 10):
        sys.exit("Python >= 3.10 requis.")
    print(f"    plateforme : {platform.platform()}")
    print(f"    RAM        : {total} Mo")


def ensure_llama_cpp(work: Path, dry: bool) -> Path:
    repo = work / "llama.cpp"
    if repo.exists():
        log("LLAMA.CPP", f"llama.cpp déjà présent ({repo})")
        return repo
    if dry:
        return repo
    log("LLAMA.CPP", "clonage de llama.cpp…")
    run(["git", "clone", "--depth", "1", LLAMA_CPP_GIT, str(repo)])
    return repo


def convert_gguf_to_hf(repo: Path, work: Path, gguf: Path, dry: bool) -> Path:
    converters = [
        repo / "tools" / "gguf" / "convert_gguf.py",
        repo / "tools" / "convert_gguf.py",
    ]
    conv = next((c for c in converters if c.exists()), converters[-1])
    out = work / "model_hf"
    log("CONVERT", f"GGUF {gguf.name} -> Safetensors fp16 (cible {out.name}/)")
    if not dry:
        run([sys.executable, str(conv), str(gguf), "--outtype", "f16", "--outfile", str(out)])
    return out


def install_abliterator(dry: bool) -> None:
    log("ABLITERATOR", "installation de FailSpy/ABliterator (python -m abliterator)")
    if not dry:
        run([sys.executable, "-m", "pip", "install", "--upgrade", "abliterator"])


def abliterate(model_dir: Path, work: Path, dry: bool) -> Path:
    out = work / "abliterated"
    log("ABLIT", f"calcul du vecteur de refus et ablation -> {out}/")
    if not dry:
        run([sys.executable, "-m", "abliterator", "--model", str(model_dir), "--output", str(out)])
    return out


def requantize(repo: Path, work: Path, abliterated: Path, out_prefix: str, dry: bool) -> Path:
    hf_conv = repo / "convert_hf_to_gguf.py"
    f16 = work / f"{out_prefix}.f16.gguf"
    final = work / f"{out_prefix}-Q4_K_M.gguf"
    log("QUANT", "conversion HF -> GGUF puis quantification Q4_K_M")
    if not dry:
        run([sys.executable, str(hf_conv), str(abliterated), "--outfile", str(f16)])
    quant = shutil.which("llama-quantize")
    if quant is None:
        quant = str(repo / "build" / "bin" / "llama-quantize")
    if not dry:
        run([str(quant), str(f16), str(final), "Q4_K_M"])
    return final


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gguf", required=True, help="Chemin du GGUF source")
    ap.add_argument("--out-prefix", default="abliterated", help="Préfixe du fichier final")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--keep-fp16", action="store_true")
    ap.add_argument("--no-pip", action="store_true")
    args = ap.parse_args()

    gguf = Path(args.gguf).resolve()
    if not gguf.exists():
        sys.exit(f"Fichier introuvable : {gguf}")
    if gguf.suffix.lower() != ".gguf":
        print(f"Attention : {gguf.suffix} n'est pas un .gguf.", file=sys.stderr)

    work = gguf.parent / f"ablit_work_{gguf.stem}"
    work.mkdir(parents=True, exist_ok=True)

    check_environment()

    llama = ensure_llama_cpp(work, args.dry_run)
    model_dir = convert_gguf_to_hf(llama, work, gguf, args.dry_run)
    if not args.no_pip:
        install_abliterator(args.dry_run)
    abliterated = abliterate(model_dir, work, args.dry_run)
    final = requantize(llama, work, abliterated, args.out_prefix, args.dry_run)

    log("TERMINÉ", f"GGUF ablité prêt : {final}")
    print("\nRamassez ce fichier, puis dans PancartPlayer :")
    print("  Onglet Modèles -> correspondance avec un modèle du catalogue.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())