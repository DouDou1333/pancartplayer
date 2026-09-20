/// Messages d'erreur amicaux en français, isolés de toute dépendance native
/// pour être unit-testables sans Platform/native. Utilisé par le service de
/// chat (bubble d'erreur) — les autres écrans en font de même si besoin.
library;

import 'package:dio/dio.dart';

/// Version tronquée à 160 caractères du détail d'une exception.
String shortErrorMessage(Object e) {
  final s = e.toString().trim();
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

/// Clé d'un message d'erreur d'API en clair et lisible.
String friendlyErrorString(Object e) {
  final s = e.toString();
  final lower = s.toLowerCase();
  final short = shortErrorMessage(e);

  final dio = e is DioException ? e : null;
  if (dio != null && dio.response?.statusCode == 404) {
    final model = _ollamaMissingModel(dio);
    if (model.isNotEmpty) {
      return 'Modèle « $model » introuvable sur Ollama — installe-le dans '
          'Termux : « ollama pull $model » (ou remplace-le par un modèle déjà '
          'installé, ex. qwen3:0.6b). Détail : $short';
    }
    return 'Réponse 404 (introuvable) — mauvaise adresse de base ou endpoint '
        'absent. Vérifie l\'URL du fournisseur (ex. http://IP:11434 sans /v1, '
        'le « /v1 » est ajouté automatiquement) et teste le service dans un '
        'navigateur. Détail : $short';
  }
  if (dio != null && dio.response?.statusCode != null) {
    final sc = dio.response!.statusCode!;
    if (sc >= 300 && sc < 400) {
      return 'Redirection HTTP ($sc) — le serveur renvoie vers une autre '
          'adresse (souvent une URL de base inexacte ou http:// → https://). '
          'Vérifie l\'adresse exacte du fournisseur (ex. http://IP:11434 pour '
          'Ollama, https:// pour le Cloud). Détail : $short';
    }
    if (sc >= 400) {
      final body = _errorBody(dio);
      return 'Réponse HTTP $sc du serveur'
          '${body.isEmpty ? '' : ' — $body'} (clé, modèle ou adresse à '
          'vérifier). Utilise « ⚙ Configurer Ollama automatiquement » ou '
          'corrige le fournisseur. Détail : $short';
    }
  }

  if (lower.contains('operation not permitted') || lower.contains('errno = 1')) {
    return 'Réseau bloqué par le système (macOS : sandbox « réseau client » ; '
        'Android : permission INTERNET). Récupère la dernière version de '
        'l\'app, ou utilise le Cloud. Détail : $short';
  }
  if (lower.contains('socketexception')) {
    return 'Connexion impossible (réseau refusé ou fournisseur éteint — pour '
        'Ollama local : lance « ollama serve » ; sinon vérifie le Wi-Fi et '
        'l\'URL). Détail : $short';
  }
  if (lower.contains('dioexception') && lower.contains('connection')) {
    return 'Connexion impossible au fournisseur — vérifie l\'URL, la clé et '
        'le réseau. Détail : $short';
  }
  if (lower.contains('cleartext')) {
    return 'Trafic HTTP non chiffré bloqué (Android). Utilise https:// ou la '
        'dernière version de l\'app (cleartext LAN autorisé). Détail : $short';
  }
  return 'Erreur : $short';
}

/// Extrait le nom d'un modèle signalé manquant par Ollama (HTTP 404 avec
/// corps `{"error": "model 'X' not found, try pulling it first"}`).
String _ollamaMissingModel(DioException e) {
  final data = e.response?.data;
  String text;
  if (data is Map) {
    final err = data['error'];
    text = err is String ? err : data.toString();
  } else if (data is String) {
    text = data;
  } else {
    return '';
  }
  final m =
      RegExp("model\\s+['\"]([^'\"]+)['\"]\\s+not found").firstMatch(text);
  return m?.group(1) ?? '';
}

/// Court extrait lisible du corps d'une réponse d'erreur (le champ `error`
/// des API OpenAI-compatibles, ou le texte brut tronqué).
String _errorBody(DioException e) {
  final data = e.response?.data;
  String text;
  if (data is Map) {
    final err = data['error'];
    text = err is String ? err : '';
  } else if (data is String) {
    text = data;
  } else {
    text = '';
  }
  final t = text.trim().replaceAll('\n', ' ');
  if (t.isEmpty) return '';
  return t.length > 140 ? '${t.substring(0, 140)}…' : t;
}

/// Vrai si l'URL pointe vers le device lui-même (`localhost`).
bool isLocalhostBaseUrl(String baseUrl) {
  final u = Uri.tryParse(baseUrl.trim());
  if (u == null) return baseUrl.trim().toLowerCase() == 'localhost';
  final host = u.host;
  return host == 'localhost' || host == '127.0.0.1' || host.isEmpty;
}

/// Message d'aide quand un provider pointe vers localhost sur mobile.
String localhostMobileHint(String baseUrl) =>
    '« localhost » sur un téléphone = le téléphone lui-même, pas ton PC.\n'
    'Pour joindre l\'Ollama du PC : remplace « $baseUrl » par '
    'http://<IP-du-PC>:11434 (ex. http://192.168.1.42:11434) et lance '
    'Ollama avec : OLLAMA_HOST=0.0.0.0 ollama serve';