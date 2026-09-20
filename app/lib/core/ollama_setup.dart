/// Détection et configuration automatique d'un serveur Ollama.
///
/// « Configurer Ollama automatiquement » : le wizard sonde uniquement cet
/// appareil (`http://127.0.0.1:11434`, `http://localhost:11434`) — pas de
/// balayage réseau (principe de l'app) — puis construit/raccroche un
/// fournisseur déjà rempli (URL détectée, modèles listés via `/v1/models`,
/// modèle par défaut choisi automatiquement).
///
/// Tout ce qui est testable sans plateforme réelle est isolé : la détection
/// accepte un `fetcher` injectable, et les fonctions (choix du modèle,
/// construction, mise à jour idempotente, instructions) sont pures.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'models.dart' show AiProvider;
import 'ollama_launcher.dart' show isOllamaProvider;

/// Issue de la détection d'un serveur Ollama local.
enum OllamaDetectStatus {
  /// Ollama répond : `/api/version` reconnu et/ou `/v1/models` listé.
  ok,

  /// Rien ne répond sur les candidats (serveur non lancé / réseau).
  unreachable,

  /// Quelque chose répond sur le port mais ce n'est pas l'API Ollama.
  notOllama,

  /// Navigateur : mixed-content (https → http) ou CORS bloqués.
  corsOrMixedContent,

  /// HTTP en clair bloqué par le système (normalement réglé dans l'app).
  cleartext,

  /// Les candidats ne répondent pas dans le délai imparti.
  timeout,
}

/// Résultat d'une détection : statut + infos utiles quand elles existent.
class OllamaDetection {
  const OllamaDetection({
    required this.status,
    this.baseUrl,
    this.version,
    this.models = const [],
  });

  final OllamaDetectStatus status;
  final String? baseUrl;
  final String? version;
  final List<String> models;

  bool get ok => status == OllamaDetectStatus.ok;
}

/// Réponse HTTP brute d'un fetch injecté (statut + corps).
class OllamaHttpResult {
  const OllamaHttpResult(this.status, this.body);

  final int status;
  final String body;
}

/// Exécution d'une requête `GET` : à injecter pour tester sans réseau.
typedef OllamaFetcher = Future<OllamaHttpResult> Function(Uri url);

/// Échec réseau structuré levé par la détection (et par les tests).
class OllamaProbeError implements Exception {
  const OllamaProbeError(this.status);

  final OllamaDetectStatus status;

  @override
  String toString() => 'OllamaProbeError($status)';
}

/// Candidats testés, dans l'ordre : le téléphone d'abord (Android/iOS), le
/// même ordinateur ensuite (desktop/web). `localhost` = cet appareil.
const List<String> kOllamaCandidates = [
  'http://127.0.0.1:11434',
  'http://localhost:11434',
];

/// URL de base d'un Ollama lui-même accessible sur cet appareil.
const String kOllamaLocalBaseUrl = 'http://127.0.0.1:11434';

Duration get _probeTimeout => const Duration(seconds: 3);

/// Sonde les candidats et renvoie la première réponse Ollama trouvée.
///
/// Ne lève jamais d'exception : renvoie toujours un `OllamaDetection` lisible.
Future<OllamaDetection> detectOllamaServer({
  OllamaFetcher? fetcher,
  List<String> candidates = kOllamaCandidates,
}) async {
  final f = fetcher ?? _defaultFetcher;
  final webHttps = kIsWeb && Uri.base.scheme == 'https';
  OllamaDetectStatus? lastIssue;

  for (final raw in candidates) {
    final base = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) continue;
    if (webHttps && base.startsWith('http://')) {
      lastIssue ??= OllamaDetectStatus.corsOrMixedContent;
      continue;
    }
    try {
      final versionRes = await f(Uri.parse('$base/api/version'));
      final version = _parseOllamaVersion(versionRes.body);
      if (version != null) {
        final models = await _fetchModels(f, Uri.parse('$base/v1/models'));
        return OllamaDetection(
          status: OllamaDetectStatus.ok,
          baseUrl: base,
          version: version,
          models: models,
        );
      }
      final openai = versionRes.status >= 200 && versionRes.status < 300
          ? await _fetchModels(f, Uri.parse('$base/v1/models'))
          : const <String>[];
      if (openai.isNotEmpty) {
        return OllamaDetection(
          status: OllamaDetectStatus.ok,
          baseUrl: base,
          models: openai,
        );
      }
      lastIssue ??= OllamaDetectStatus.notOllama;
    } on OllamaProbeError catch (e) {
      lastIssue ??= e.status;
    } on Object {
      lastIssue ??= OllamaDetectStatus.unreachable;
    }
  }
  return OllamaDetection(status: lastIssue ?? OllamaDetectStatus.unreachable);
}

Future<OllamaHttpResult> _defaultFetcher(Uri url) async {
  try {
    final res = await Dio(
      BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
      ),
    ).get<String>(
      url.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'Accept': 'application/json'},
      ),
    );
    return OllamaHttpResult(res.statusCode ?? 0, res.data ?? '');
  } on DioException catch (e) {
    final sc = e.response?.statusCode;
    if (sc != null) {
      final data = e.response?.data;
      return OllamaHttpResult(sc, data == null ? '' : data.toString());
    }
    final msg = (e.message ?? '').toLowerCase();
    if (msg.contains('cleartext')) {
      throw const OllamaProbeError(OllamaDetectStatus.cleartext);
    }
    if (msg.contains('cors') || msg.contains('failed to fetch')) {
      throw const OllamaProbeError(OllamaDetectStatus.corsOrMixedContent);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      throw const OllamaProbeError(OllamaDetectStatus.timeout);
    }
    throw const OllamaProbeError(OllamaDetectStatus.unreachable);
  }
}

Future<List<String>> _fetchModels(OllamaFetcher f, Uri url) async {
  try {
    final r = await f(url);
    if (r.status < 200 || r.status >= 300) return const [];
    return _parseModelIds(r.body);
  } on OllamaProbeError {
    return const [];
  } on Object {
    return const [];
  }
}

/// Serait vrai si le corps est celui d'un `/api/version` Ollama.
String? _parseOllamaVersion(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['version'] is String) {
      final v = (j['version'] as String).trim();
      if (v.isNotEmpty) return v;
    }
  } catch (_) {
    // corps non-JSON -> ce n'est pas Ollama (ni une API ouverte ici)
  }
  return null;
}

/// Extrait les ids de `/v1/models` (OpenAI-compatible) : `data[].id`.
List<String> _parseModelIds(String body) {
  if (body.trim().isEmpty) return const [];
  try {
    final j = jsonDecode(body);
    if (j is Map && j['data'] is List) {
      final out = <String>[];
      for (final o in j['data'] as List) {
        if (o is Map && o['id'] is String) {
          final id = (o['id'] as String).trim();
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    }
  } catch (_) {
    // corps illisible -> pas de modèle exploitable
  }
  return const [];
}

/// Modèle par défaut le plus raisonnable parmi les ids listés.
///
/// Préfère un `qwen` non-`:latest` (ex. `qwen3:0.6b`, léger et adapté au
/// RAM des téléphones), sinon le premier id non-`:latest`, sinon le premier.
String suggestOllamaModel(List<String> ids) {
  String? anyNonLatest;
  String? qwen;
  for (final raw in ids) {
    final id = raw.trim();
    if (id.isEmpty) continue;
    final isLatest = id.endsWith(':latest');
    if (!isLatest) {
      anyNonLatest ??= id;
      if (id.toLowerCase().contains('qwen')) qwen ??= id;
    }
  }
  return qwen ?? anyNonLatest ?? (ids.isEmpty ? '' : ids.first.trim());
}

/// Nom à donner au fournisseur selon l'hôte saisi.
String ollamaProviderName(String baseUrl) {
  final u = Uri.tryParse(baseUrl.trim());
  final host = u?.host.isEmpty == false ? u!.host : '';
  return (host == '127.0.0.1' || host == 'localhost' || host.isEmpty)
      ? 'Ollama (téléphone)'
      : 'Ollama (réseau local)';
}

/// Construit un fournisseur Ollama prêt à sauvegarder (id stable).
AiProvider buildOllamaProvider({
  required String baseUrl,
  required String model,
  String? name,
}) =>
    AiProvider(
      id: 'ollama_local',
      name: name ?? ollamaProviderName(baseUrl),
      kind: 'remote',
      baseUrl: baseUrl.trim(),
      apiKey: '',
      defaultModel: model.trim(),
      isEnabled: true,
    );

/// Retrouve le fournisseur Ollama existant (nom, URL ou port 11434), s'il y
/// en a un — évite les doublons.
AiProvider? findOllamaProvider(List<AiProvider> providers) {
  for (final p in providers) {
    if (isOllamaProvider(p)) return p;
  }
  return null;
}

/// Crée ou met à jour le fournisseur Ollama : jamais de doublon, et rien
/// d'autre n'est modifié (le nom et la clef de l'existant sont conservés).
///
/// Renvoie le fournisseur à sauvegarder (créé ou réutilisé).
AiProvider resolveOllamaProvider({
  required List<AiProvider> providers,
  required String baseUrl,
  required String model,
}) {
  final existing = findOllamaProvider(providers);
  if (existing != null) {
    existing.baseUrl = baseUrl.trim();
    existing.defaultModel = model.trim();
    return existing;
  }
  return buildOllamaProvider(baseUrl: baseUrl, model: model);
}

/// Une étape de configuration : un titre lisible + la commande à copier.
class OllamaStep {
  const OllamaStep(this.title, this.command);

  final String title;
  final String command;
}

/// Étapes de mise en place pour Ollama DANS Termux (sur le téléphone).
List<OllamaStep> ollamaSetupSteps() => const [
      OllamaStep('Mets à jour Termux', 'pkg update -y && pkg upgrade -y'),
      OllamaStep('Installe le serveur Ollama', 'pkg install -y ollama'),
      OllamaStep('Télécharge un modèle léger', 'ollama pull qwen3:0.6b'),
      OllamaStep(
          'Démarre le serveur', 'OLLAMA_HOST=127.0.0.1:11434 ollama serve'),
      OllamaStep(
        'Autostart au démarrage de Termux (optionnel)',
        "mkdir -p ~/.termux/boot && printf '#!/bin/sh\\n"
        "pgrep -x ollama >/dev/null || OLLAMA_HOST=127.0.0.1:11434 ollama serve\\n' "
        "> ~/.termux/boot/ollama.sh && chmod 700 ~/.termux/boot/ollama.sh",
      ),
      OllamaStep(
        'Autorise l\'app à lancer Termux (optionnel)',
        'echo "allow-external-apps=true" >> ~/.termux/termux.properties',
      ),
    ];

/// Étapes de mise en place pour un Ollama sur un ordinateur (PC/Mac/Linux),
/// rejoignable depuis un autre appareil du réseau.
List<OllamaStep> ollamaPcSteps() => const [
      OllamaStep('Installe Ollama', 'voir https://ollama.com'),
      OllamaStep('Télécharge un modèle léger', 'ollama pull qwen3:0.6b'),
      OllamaStep('Démarre le serveur', 'ollama serve'),
      OllamaStep(
        'Expose sur le réseau (pour joindre depuis un autre appareil)',
        'OLLAMA_HOST=0.0.0.0:11434 ollama serve',
      ),
    ];

/// Aide contextuelle selon la plateforme (affichée en cas d'échec).
String platformOllamaHint() {
  if (kIsWeb) {
    return 'Sur le web, joindre http://127.0.0.1:11434 ne marche que si '
        'l\'app est servie en http:// (pas https, sinon mixed-content). '
        'Sinon, utilise l\'app de bureau ou mobile.';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'Sur Android, Ollama tourne dans l\'app Termux de CE téléphone — '
        'les commandes ci-dessous s\'exécutent dans Termux.';
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return 'Sur iPhone/iPad, Ollama peut tourner dans un terminal Unix local '
        '(ex. iSH) ou sur le PC — voir les étapes « ordinateur » plus bas.';
  }
  return 'Sur cet ordinateur, http://127.0.0.1:11434 désigne l\'Ollama '
      'installé sur cette machine.';
}

/// Message français d'un résultat de détection.
String ollamaDetectMessage(OllamaDetection d) {
  switch (d.status) {
    case OllamaDetectStatus.ok:
      final v = d.version == null ? '' : ' — version ${d.version}';
      final mods = d.models.isEmpty
          ? 'aucun modèle installé'
          : '${d.models.length} modèle(s) : ${d.models.join(', ')}';
      return 'Ollama détecté ✓ sur ${d.baseUrl}$v\n$mods.';
    case OllamaDetectStatus.notOllama:
      return 'Un service répond sur ${d.baseUrl ?? 'le port 11434'} '
          'mais ce n\'est pas l\'API d\'Ollama.';
    case OllamaDetectStatus.unreachable:
      return 'Rien ne répond sur $kOllamaLocalBaseUrl — Ollama n\'est '
          'pas lancé.';
    case OllamaDetectStatus.timeout:
      return 'Délai dépassé sur $kOllamaLocalBaseUrl — le serveur ne '
          'répond pas à temps.';
    case OllamaDetectStatus.cleartext:
      return 'HTTP local bloqué par le système. Utilise la dernière version '
          'de l\'app (cleartext LAN autorisé).';
    case OllamaDetectStatus.corsOrMixedContent:
      return 'Impossible de joindre $kOllamaLocalBaseUrl depuis le '
          'navigateur (mixed-content ou CORS). Sers l\'app en http:// ou '
          'utilise l\'app mobile/bureau.';
  }
}