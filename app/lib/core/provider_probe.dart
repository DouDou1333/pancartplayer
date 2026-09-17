/// Vérification ponctuelle d'un fournisseur : teste UNIQUEMENT l'URL saisie.
///
/// Pas de balayage réseau : PancartPlayer se configure par fournisseur
/// (URL + clé + modèle), comme toute app d'IA. Le « Tester la connexion »
/// essaie `/api/version` (Ollama) et `/v1/models` (OpenAI-compatible) et
/// explique simplement le premier échec. Web-safe.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

const Duration _probeTimeout = Duration(seconds: 4);

/// Résultat d'un test : joignable ou non, avec un message clair en français.
class ProviderProbeResult {
  const ProviderProbeResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Vrai si un corps de réponse `/api/version` correspond à Ollama.
bool isOllamaVersionJson(String body) {
  if (body.trim().isEmpty) return false;
  try {
    final j = jsonDecode(body);
    return j is Map && j['version'] is String && (j['version'] as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Vrai si un corps de réponse `/v1/models` correspond à une API
/// OpenAI-compatible (liste non vide ou 401 non capturé).
bool isOpenAiModelsJson(String body) {
  if (body.trim().isEmpty) return false;
  try {
    final j = jsonDecode(body);
    return j is Map && j['data'] is List;
  } catch (_) {
    return false;
  }
}

/// Teste l'URL de base d'un fournisseur (sans balayage réseau).
Future<ProviderProbeResult> probeProviderUrl(
  String baseUrl, {
  String apiKey = '',
  Duration timeout = _probeTimeout,
}) async {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty ||
      (!base.startsWith('http://') && !base.startsWith('https://'))) {
    return const ProviderProbeResult(
      false,
      'URL invalide — ex. https://api.openai.com ou http://192.168.1.20:11434',
    );
  }

  final paths = <String>{
    if (base.contains('11434') || base.toLowerCase().contains('localhost'))
      '$base/api/version',
    '$base/v1/models',
    '$base/api/version',
  };

  for (final path in paths) {
    final r = await _tryPath(path, apiKey: apiKey, timeout: timeout);
    if (r != null) return r;
  }
  return const ProviderProbeResult(
    false,
    'Aucune réponse — vérifie l\'adresse, la clé et le Wi-Fi.',
  );
}

Future<ProviderProbeResult?> _tryPath(
  String url, {
  required String apiKey,
  required Duration timeout,
}) async {
  try {
    final res = await Dio().get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ),
    );
    final body = res.data ?? '';
    if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
      if (url.endsWith('/api/version') ? isOllamaVersionJson(body) : isOpenAiModelsJson(body)) {
        return const ProviderProbeResult(true, 'Fournisseur joignable ✓');
      }
      return const ProviderProbeResult(true, 'Fournisseur joignable ✓ (réponse incomprise)');
    }
    return ProviderProbeResult(false, 'Réponse ${res.statusCode} — endpoint incorrect ?');
  } on DioException catch (e) {
    final t = e.type;
    final sc = e.response?.statusCode;
    if (t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout) {
      return const ProviderProbeResult(
        false,
        'Délai dépassé — machine injoignable (réseau, pare-feu Ou VPN) ?',
      );
    }
    if (t == DioExceptionType.connectionError) {
      return const ProviderProbeResult(
        false,
        'Connexion impossible — adresse correcte ? Wi-Fi actif ? Ollama lancé ?',
      );
    }
    if (sc == 401 || sc == 403) {
      return ProviderProbeResult(false, 'Accès refusé ($sc) — clé API invalide ?');
    }
    if (sc == 404) {
      return const ProviderProbeResult(
        false,
        'Endpoint introuvable (404) — adresse de base erronée ?',
      );
    }
    return ProviderProbeResult(false, 'Erreur serveur ($sc) — détail : ${e.message}');
  } on Object catch (e) {
    return ProviderProbeResult(false, 'Test impossible : $e');
  }
}