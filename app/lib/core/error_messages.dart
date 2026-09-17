/// Messages d'erreur amicaux en français, isolés de toute dépendance native
/// pour être unit-testables sans Platform/native. Utilisé par le service de
/// chat (bubble d'erreur) — les autres écrans en font de même si besoin.
library;

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