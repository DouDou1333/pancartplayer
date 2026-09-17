import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/models.dart';

void main() {
  group('Models JSON round-trip', () {
    test('AiProvider', () {
      final p = AiProvider(
        id: 'x',
        name: 'OpenAI',
        kind: 'remote',
        baseUrl: 'https://api.openai.com',
        defaultModel: 'gpt-4o-mini',
      );
      final back = AiProvider.fromJson(p.toJson());
      expect(back.id, 'x');
      expect(back.name, 'OpenAI');
      expect(back.kind, 'remote');
    });

    test('CatalogModel', () {
      final m = CatalogModel(
        id: 'qwen3-4b',
        name: 'Qwen3 4B',
        owner: 'unsloth',
        repo: 'unsloth/Qwen3-4B-GGUF',
        file: 'Qwen3-4B-Q4_K_M.gguf',
        params: '3.8B',
        sizeMb: 2370,
        recommendedFor: 'all',
      );
      final back = CatalogModel.fromJson(m.toJson());
      expect(back.id, 'qwen3-4b');
      expect(back.downloadUrl(),
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf');
    });

    test('CatalogModel.fromHfUrl import URL', () {
      final m = CatalogModel.fromHfUrl(
        url:
            'https://huggingface.co/mradermacher/Ornicrat-9B-GGUF/resolve/main/ornith-9b-uncensored-Q4_K_M.gguf',
      );
      expect(m.id, 'custom-ornith-9b-uncensored-q4-k-m');
      expect(m.owner, 'mradermacher');
      expect(m.file, 'ornith-9b-uncensored-Q4_K_M.gguf');
      expect(m.repo, 'https://huggingface.co/mradermacher/Ornicrat-9B-GGUF/resolve/main/ornith-9b-uncensored-Q4_K_M.gguf');
      expect(m.hfUrl, isFalse);
      expect(m.downloadUrl(),
          'https://huggingface.co/mradermacher/Ornicrat-9B-GGUF/resolve/main/ornith-9b-uncensored-Q4_K_M.gguf');
      final back = CatalogModel.fromJson(m.toJson());
      expect(back.id, m.id);
      expect(back.downloadUrl(), m.downloadUrl());
    });

    test('CatalogModel.fromFilePath import fichier', () {
      final m = CatalogModel.fromFilePath('Mon-Resultat-Q4_K_M.gguf');
      expect(m.id, 'custom-mon-resultat-q4-k-m');
      expect(m.id.startsWith('custom-'), isTrue);
      expect(m.repo, 'import local');
      expect(m.hfUrl, isFalse);
      final back = CatalogModel.fromJson(m.toJson());
      expect(back.id, m.id);
      expect(back.downloadUrl(), m.downloadUrl());
      final weird = CatalogModel.fromFilePath('../../../tmp/foo bar.bin');
      expect(weird.id, isNotEmpty);
    });

    test('Conversation with messages', () {
      final conv = Conversation(
        id: 'c1',
        title: 'Titre',
        providerId: 'p',
        modelId: 'm',
        createdAt: DateTime.now(),
      );
      conv.messages.add(ChatMessage(role: 'user', content: 'bonjour'));
      conv.messages.add(ChatMessage(role: 'assistant', content: 'salut'));
      final back = Conversation.fromJson(conv.toJson());
      expect(back.messages.length, 2);
      expect(back.messages[1].content, 'salut');
      expect(back.preview().contains('salut'), isTrue);
    });

    test('AblitJob', () {
      final j = AblitJob(
        id: 'job1',
        sourceModelName: 'model.gguf',
        state: AblitState.running,
        step: 'Conversion',
      );
      final back = AblitJob.fromJson(j.toJson());
      expect(back.state, AblitState.running);
      expect(back.step, 'Conversion');
    });
  });
}