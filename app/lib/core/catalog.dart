/// Catalogue de modèles GGUF soigneusement choisis (tailles réelles).
///
/// `recommendedFor` indique l'appareil conseillé :
///   - 'phone'   : <= ~1,2 Go  — convient à un smartphone RAM réduite
///   - 'all'     : <= ~3 Go    — smartphones costauds et ordinateurs
///   - 'desktop' : > 3 Go      — machines équipées
library;

import 'models.dart';

/// Plafond de RAM (en Mo) pour l'exécution LOCALE sur appareil mobile.
/// Les modèles plus lourds doivent être servis par le cloud.
/// 3200 Mo couvre gemma-3-4b (3020 Mo) mais exclut les ~5 Go (Ornith-9B…).
const int kLocalRamLimitMb = 3200;

const List<CatalogModel> kCatalog = [
  // ---- Phoniques (RAM réduite) ----------------------------------------
  CatalogModel(
    id: 'qwen3-0.6b',
    name: 'Qwen3 0.6B',
    owner: 'unsloth',
    repo: 'unsloth/Qwen3-0.6B-GGUF',
    file: 'Qwen3-0.6B-Q4_K_M.gguf',
    params: '0.6B',
    quant: 'Q4_K_M',
    sizeMb: 460,
    recommendedFor: 'phone',
    tags: ['general', 'rapide'],
  ),
  CatalogModel(
    id: 'qwen3-1.7b',
    name: 'Qwen3 1.7B',
    owner: 'unsloth',
    repo: 'unsloth/Qwen3-1.7B-GGUF',
    file: 'Qwen3-1.7B-Q4_K_M.gguf',
    params: '1.7B',
    quant: 'Q4_K_M',
    sizeMb: 1010,
    recommendedFor: 'phone',
    tags: ['general', 'rapide'],
  ),
  CatalogModel(
    id: 'llama3.2-1b',
    name: 'Llama 3.2 1B',
    owner: 'unsloth',
    repo: 'unsloth/Llama-3.2-1B-GGUF',
    file: 'Llama-3.2-1B-Q4_K_M.gguf',
    params: '1.1B',
    quant: 'Q4_K_M',
    sizeMb: 840,
    recommendedFor: 'phone',
    tags: ['general'],
  ),

  // ---- Universels (smartphones + ordinateurs) --------------------------
  CatalogModel(
    id: 'qwen3-4b',
    name: 'Qwen3 4B',
    owner: 'unsloth',
    repo: 'unsloth/Qwen3-4B-GGUF',
    file: 'Qwen3-4B-Q4_K_M.gguf',
    params: '3.8B',
    quant: 'Q4_K_M',
    sizeMb: 2370,
    recommendedFor: 'all',
    tags: ['general', 'conseillé'],
  ),
  CatalogModel(
    id: 'llama3.2-3b',
    name: 'Llama 3.2 3B',
    owner: 'unsloth',
    repo: 'unsloth/Llama-3.2-3B-GGUF',
    file: 'Llama-3.2-3B-Q4_K_M.gguf',
    params: '3.2B',
    quant: 'Q4_K_M',
    sizeMb: 2070,
    recommendedFor: 'all',
    tags: ['general'],
  ),
  CatalogModel(
    id: 'gemma3-4b',
    name: 'Gemma 3 4B',
    owner: 'unsloth',
    repo: 'unsloth/gemma-3-4b-it-GGUF',
    file: 'gemma-3-4b-it-Q4_K_M.gguf',
    params: '4B',
    quant: 'Q4_K_M',
    sizeMb: 3020,
    recommendedFor: 'all',
    tags: ['multimodal', 'conseillé'],
  ),
  CatalogModel(
    id: 'phi3.5-mini',
    name: 'Phi-3.5 Mini',
    owner: 'unsloth',
    repo: 'unsloth/Phi-3.5-mini-instruct-GGUF',
    file: 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
    params: '3.8B',
    quant: 'Q4_K_M',
    sizeMb: 2250,
    recommendedFor: 'all',
    tags: ['code', 'raisonnement'],
  ),

  // ---- Desktop ----------------------------------------------------------
  CatalogModel(
    id: 'ornith-1.5-9b',
    name: 'Ornith 1.5 9B',
    owner: 'ornith-ai',
    repo: 'ornith-ai/Ornith-1.5-9B-GGUF',
    file: 'Ornith-1.5-9B-Q4_K_M.gguf',
    params: '9B',
    quant: 'Q4_K_M',
    sizeMb: 4820,
    recommendedFor: 'desktop',
    tags: ['roleplay', 'uncensored'],
  ),
  CatalogModel(
    id: 'qwen3-8b',
    name: 'Qwen3 8B',
    owner: 'Qwen',
    repo: 'Qwen/Qwen3-8B-GGUF',
    file: 'Qwen3-8B-Q4_K_M.gguf',
    params: '8B',
    quant: 'Q4_K_M',
    sizeMb: 4900,
    recommendedFor: 'desktop',
    tags: ['general'],
  ),
];

CatalogModel? catalogById(String id) {
  for (final m in kCatalog) {
    if (m.id == id) return m;
  }
  return null;
}

/// Cherche dans le catalogue de base, puis dans une liste de modèles custom
/// (importés par URL Hugging Face).
CatalogModel? catalogByIdOrCustom(String id, List<CatalogModel> customs) {
  final base = catalogById(id);
  if (base != null) return base;
  for (final m in customs) {
    if (m.id == id) return m;
  }
  return null;
}