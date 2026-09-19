/// Lancement d'un serveur local Ollama depuis l'application.
///
/// Déroulé :
///  1. Tester le fournisseur (probe, sans balayage réseau).
///  2. S'il est injoignable et pointe vers le téléphone lui-même (localhost/Android)
///     : envoyer un intent Termux `RUN_COMMAND` pour lancer `ollama serve`.
///  3. Sinon : fournir la commande exacte à copier selon le scénario
///     (serveur sur cet appareil, ou Ollama sur un PC du réseau local).
///
/// Les fonctions pures (prédicats, phrases, extras d'intent) sont isolées
/// pour être testables sans plateforme réelle.
library;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:android_intent_plus/android_intent_plus.dart';

import 'error_messages.dart' show isLocalhostBaseUrl;
import 'models.dart' show AiProvider;
import 'provider_probe.dart' show probeProviderUrl;

/// Chemin du shell Termux (côté Android).
const String kTermuxBash = '/data/data/com.termux/files/usr/bin/bash';

/// Répertoire personnel Termux.
const String kTermuxHome = '/data/data/com.termux/files/home';

/// Commande à lancer SUR l'appareil pour démarrer Ollama local.
String ollamaServeCommand() => 'OLLAMA_HOST=127.0.0.1:11434 ollama serve';

/// Commande à lancer sur un PC pour exposer Ollama sur le Wi-Fi.
String ollamaServeCommandOnPc() => 'OLLAMA_HOST=0.0.0.0:11434 ollama serve';

/// Vrai si le fournisseur ressemble à un Ollama (nom ou URL/port).
bool isOllamaProvider(AiProvider p) {
  final name = p.name.toLowerCase();
  final url = p.baseUrl.toLowerCase();
  return name.contains('ollama') ||
      url.contains('ollama') ||
      url.contains(':11434');
}

/// Vrai si l'URL désigne le téléphone lui-même sous Android (hors web).
bool isAndroidLocalhostProvider(AiProvider p) =>
    isLocalhostBaseUrl(p.baseUrl) &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android;

/// Extras de l'intent Termux `RUN_COMMAND` qui lance `ollama serve` en fond.
Map<String, dynamic> termuxRunCommandArgs() => {
      'com.termux.RUN_COMMAND_PATH': kTermuxBash,
      'com.termux.RUN_COMMAND_ARGUMENTS': <String>['-c', ollamaServeCommand()],
      'com.termux.RUN_COMMAND_WORKDIR': kTermuxHome,
      'com.termux.RUN_COMMAND_BACKGROUND': true,
    };

/// Copie `text` dans le presse-papiers (échoue sans erreur si indisponible).
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on Object {
    return false;
  }
}

/// Envoie l'intent Termux ; vrai si le service a accepté le lancement.
Future<bool> _tryTermuxLaunch() async {
  try {
    final intent = AndroidIntent(
      action: 'com.termux.RUN_COMMAND',
      package: 'com.termux',
      componentName: 'com.termux/.app.RunCommandService',
      arguments: termuxRunCommandArgs(),
    );
    await intent.sendService();
    return true;
  } on Object {
    // Termux absent, permission non accordée, ou « allow external apps »
    // désactivé -> laissé à l'UI d'expliquer.
    return false;
  }
}

/// Issue d'une tentative de démarrage.
enum OllamaStartStatus { running, started, instructions }

class OllamaStartResult {
  const OllamaStartResult(this.status, this.message, {this.command});

  final OllamaStartStatus status;

  /// Message français affiché à l'utilisateur.
  final String message;

  /// Commande à copier (si pertinente) via le bouton « Copier la commande ».
  final String? command;
}

/// Essaie de rendre le `Ollama` du fournisseur `p` joignable.
///
/// Ne quitte jamais sur une erreur : renvoie toujours une issue lisible.
Future<OllamaStartResult> startOllama(AiProvider p) async {
  final probe = await probeProviderUrl(p.baseUrl, apiKey: p.apiKey);
  if (probe.ok) {
    return OllamaStartResult(
      OllamaStartStatus.running,
      'Ollama est déjà lancé ✓ : ${probe.message}',
      command: ollamaServeCommand(),
    );
  }

  if (isAndroidLocalhostProvider(p)) {
    if (await _tryTermuxLaunch()) {
      await Future<void>.delayed(const Duration(seconds: 6));
      final after = await probeProviderUrl(p.baseUrl, apiKey: p.apiKey);
      if (after.ok) {
        return const OllamaStartResult(
          OllamaStartStatus.started,
          'Ollama a démarré sur le téléphone ✓ — le fournisseur est joignable.',
          command: ollamaServeCommand(),
        );
      }
      return const OllamaStartResult(
        OllamaStartStatus.started,
        'Commande envoyée à Termux — Ollama est en train de démarrer.\n'
        'Réessaie la connexion dans quelques secondes.',
        command: ollamaServeCommand(),
      );
    }
    return const OllamaStartResult(
      OllamaStartStatus.instructions,
      'Impossible de lancer Termux depuis l\'app. Pour le permettre :\n'
      '⒈ Termux → « long-press » sur l\'écran → More → Help/Settings (ou '
      'redémarre Termux) pour charger :\n'
      '   echo "allow-external-apps=true" >> ~/.termux/termux.properties\n'
      '⒉ Paramètres Android → PancartPlayer → Autorisations → '
      '« Autorisations supplémentaires » → autoriser « Exécuter des '
      'commandes dans Termux ».\n'
      'Sinon, copie la commande et colle-la dans Termux :',
      command: ollamaServeCommand(),
    );
  }

  if (isLocalhostBaseUrl(p.baseUrl)) {
    return const OllamaStartResult(
      OllamaStartStatus.instructions,
      'Lance Ollama dans le terminal de cet appareil puis réessaie :',
      command: ollamaServeCommand(),
    );
  }

  return const OllamaStartResult(
    OllamaStartStatus.instructions,
    'Ollama n\'est pas joignable à cette adresse. Sur le PC où il tourne,\n'
    'lance la commande ci-dessous pour l\'exposer sur le Wi-Fi :',
    command: ollamaServeCommandOnPc(),
  );
}