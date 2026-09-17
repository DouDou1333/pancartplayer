import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/provider_probe.dart';

void main() {
  group('isOllamaVersionJson', () {
    test('admet la réponse réelle d\'Ollama', () {
      expect(isOllamaVersionJson('{"version":"0.5.4"}'), isTrue);
    });

    test('refuse un service qui répond autre chose', () {
      expect(isOllamaVersionJson('{"status":"ok"}'), isFalse);
      expect(isOllamaVersionJson('404 page not found'), isFalse);
      expect(isOllamaVersionJson(''), isFalse);
    });

    test('refuse un version non-chaîne', () {
      expect(isOllamaVersionJson('{"version":123}'), isFalse);
    });
  });

  group('isOpenAiModelsJson', () {
    test('admet /v1/models', () {
      expect(isOpenAiModelsJson('{"data":[{"id":"gpt-4o-mini"}]}'), isTrue);
      expect(isOpenAiModelsJson('{"data":[]}'), isTrue);
    });

    test('refuse les autres corps', () {
      expect(isOpenAiModelsJson('{"error":"x"}'), isFalse);
      expect(isOpenAiModelsJson('nimporte quoi'), isFalse);
    });
  });

  group('probeProviderUrl (validation d\'URL, aucun réseau)', () {
    test('quoi URL invalide est rejetée sans appel réseau', () async {
      final r = await probeProviderUrl('');
      expect(r.ok, isFalse);
      expect(r.message, contains('URL invalide'));

      final r2 = await probeProviderUrl('192.168.1.20:11434');
      expect(r2.ok, isFalse);
      expect(r2.message, contains('URL invalide'));
    });
  });
}