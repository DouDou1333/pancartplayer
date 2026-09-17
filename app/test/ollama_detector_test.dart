import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/ollama_detector.dart';

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
}