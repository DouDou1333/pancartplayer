/// Orchestration du chat : fait tourner n'importe quel fournisseur
/// (local ou distant) et stocke l'historique dans la conversation.
library;

import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'models.dart';
import 'storage.dart';
import 'remote_client.dart';
import 'local_engine.dart';
import 'catalog.dart';
import 'engine_support.dart';
import 'error_messages.dart';

class ChatService {
  ChatService(this._store);

  final AppStore _store;

  /// Envoie `text` dans `conv` et renvoie immédiatement la liste à jour
  /// des messages (videra automatiquement la store à chaque token).
  ///
  /// Le message assistant est ajouté et servira de buffer de streaming ;
  /// `onTick` permet à l'UI de se rafraîchir à la volée.
  Future<Conversation> send({
    required Conversation conv,
    required String text,
    Function()? onTick,
  }) async {
    conv.messages.add(ChatMessage(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    ));
    await _store.saveConversation(conv);

    final assistant = ChatMessage(
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    conv.messages.add(assistant);

    final storedProvider = _store.provider(conv.providerId);
    final isLocal = conv.providerId == 'local' || storedProvider?.kind == 'local';
    if (!isLocal && storedProvider == null) {
      assistant.error = 'Fournisseur introuvable.';
      assistant.isStreaming = false;
      await _store.saveConversation(conv);
      return conv;
    }

    final systemPrompt = _store.getString(
        'system_prompt', 'Tu es un assistant utile et précis.');
    final temperature = _store.getDouble('temperature', 0.7);

    final historyMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...conv.messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content}),
    ];

    try {
      final Stream<String> stream;
      if (!isLocal) {
        final provider = storedProvider!;
        final client = RemoteClient(
          baseUrl: provider.baseUrl,
          apiKey: await _store.readKey(provider.id),
        );
        stream = client.streamReply(
          model: conv.modelId.isEmpty ? provider.defaultModel : conv.modelId,
          messages: historyMessages,
          temperature: temperature,
        );
      } else {
        final reason = localEngineUnsupportedReason();
        if (reason != null) {
          assistant.error =
              'Moteur local indisponible — $reason Tu peux continuer en Cloud.';
          assistant.isStreaming = false;
          await _store.saveConversation(conv);
          return conv;
        }
        final customs = _store.customModels();
        final cat = catalogByIdOrCustom(conv.modelId, customs);
        if (cat != null && cat.sizeMb > kLocalRamLimitMb) {
          assistant.error =
              'Modèle trop lourd pour le local (${(cat.sizeMb / 1000).toStringAsFixed(1)} Go). '
              'Passe ce modèle en Cloud (onglet « IA » / badge moteur) pour '
              '${(cat.sizeMb / 1000).toStringAsFixed(0)}+ Go.';
          assistant.isStreaming = false;
          await _store.saveConversation(conv);
          return conv;
        }
        final local = _deviceModel(conv.modelId);
        if (local == null || !local.isDownloaded) {
          assistant.error =
              'Modèle local introuvable : télécharge-le d\'abord dans '
              'l\'onglet « Modèles ».';
          assistant.isStreaming = false;
          await _store.saveConversation(conv);
          return conv;
        }
        try {
          await LocalEngine.instance.loadModel(local.localPath);
        } on Object catch (e) {
          assistant.error = 'Impossible de charger le moteur local '
              '(modèle incompatible ou système trop ancien). Passe ce chat '
              'en Cloud via le bandeau « changer local / cloud ». Détail : ${_short(e)}';
          assistant.isStreaming = false;
          await _store.saveConversation(conv);
          return conv;
        }
        stream = LocalEngine.instance.complete(
          messages: historyMessages,
          temperature: temperature,
        );
      }

      await for (final delta in stream) {
        assistant.content += delta;
        onTick?.call();
      }
    } on Object catch (e) {
      assistant.error = await _errorMessage(e, storedProvider);
    } finally {
      assistant.isStreaming = false;
      await _store.saveConversation(conv);
    }
    return conv;
  }

  /// Persiste le changement de moteur/modèle d'une conversation existante.
  Future<void> setEngine(Conversation conv) => _store.saveConversation(conv);

  DeviceModel? _deviceModel(String catalogId) {
    for (final d in _store.deviceModels()) {
      if (d.catalogId == catalogId) return d;
    }
    return null;
  }

  static String _short(Object e) {
    final s = e.toString().trim();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  /// Transforme une erreur de transport en message amical en français
  /// (délégation aux fonctions pures de `error_messages.dart`).
  static String _friendlyError(Object e) => friendlyErrorString(e);

/// Message d'erreur final. Sur mobile, un fournisseur `localhost` est
  /// absurde (localhost = l'appareil) : on guide vers une configuration
  /// correcte au lieu de scanner le réseau.
  Future<String> _errorMessage(Object e, AiProvider? provider) async {
    final short = _short(e);
    final isConnectionError = e is SocketException ||
        (e.toString().contains('DioException') &&
            e.toString().toLowerCase().contains('connection'));

    if (isConnectionError &&
        provider != null &&
        _isLocalhostUrl(provider.baseUrl) &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'Sur un téléphone, « localhost » désigne le téléphone lui-même, '
          'pas ton PC. Ajoute ton fournisseur dans l\'onglet « IA » avec ses '
          'infos habituelles : URL de ton machine (ex. http://192.168.1.20:11434 '
          'pour Ollama, ou l\'URL du Cloud), clé API, modèle. Détail : $short';
    }
    if (isConnectionError &&
        provider == null &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'Connexion impossible (fournisseur vide ou réseau). Ajoute un '
          'fournisseur dans l\'onglet « IA » : URL, clé, modèle. Détail : $short';
    }

    return _friendlyError(e);
  }

  static bool _isLocalhostUrl(String s) {
    final u = Uri.tryParse(s);
    final host = u?.host.isEmpty == false ? u!.host : s.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '[::1]';
  }
}