/// Orchestration du chat : fait tourner n'importe quel fournisseur
/// (local ou distant) et stocke l'historique dans la conversation.
library;

import 'models.dart';
import 'storage.dart';
import 'remote_client.dart';
import 'local_engine.dart';

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

    final provider = _store.provider(conv.providerId);
    if (provider == null) {
      assistant.error = 'Fournisseur introuvable.';
      assistant.isStreaming = false;
      await _store.saveConversation(conv);
      return conv;
    }

    final historyMessages = [
      {'role': 'system', 'content': 'Tu es un assistant utile et précis.'},
      ...conv.messages
          .where((m) => !m.isStreaming)
          .map((m) => {'role': m.role, 'content': m.content}),
    ];

    try {
      final Stream<String> stream;
      if (provider.kind == 'remote') {
        final client = RemoteClient(
          baseUrl: provider.baseUrl,
          apiKey: await _store.readKey(provider.id),
        );
        stream = client.streamReply(
          model: conv.modelId.isEmpty ? provider.defaultModel : conv.modelId,
          messages: historyMessages,
        );
      } else {
        final local = _deviceModel(conv.modelId);
        if (local == null || !local.isDownloaded) {
          assistant.error =
              'Télécharge d\'abord le modèle local (onglet Modèles), puis '
              'modifie le modèle de la conversation (identifiant catalogue).';
          assistant.isStreaming = false;
          await _store.saveConversation(conv);
          return conv;
        }
        await LocalEngine.instance.loadModel(local.localPath);
        stream = LocalEngine.instance.complete(
          messages: historyMessages,
        );
      }

      await for (final delta in stream) {
        assistant.content += delta;
        onTick?.call();
      }
    } on Object catch (e) {
      assistant.error = 'Erreur : $e';
    } finally {
      assistant.isStreaming = false;
      await _store.saveConversation(conv);
    }
    return conv;
  }

  DeviceModel? _deviceModel(String catalogId) {
    for (final d in _store.deviceModels()) {
      if (d.catalogId == catalogId) return d;
    }
    return null;
  }
}