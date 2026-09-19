import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/models.dart';
import 'package:pancartplayer/core/ollama_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('commandes', () {
    test('la commande locale lance ollama sur 127.0.0.1:11434', () {
      expect(ollamaServeCommand(),
          'OLLAMA_HOST=127.0.0.1:11434 ollama serve');
    });

    test('la commande PC expose ollama sur le réseau local', () {
      expect(ollamaServeCommandOnPc(),
          'OLLAMA_HOST=0.0.0.0:11434 ollama serve');
    });
  });

  group('isOllamaProvider', () {
    AiProvider p(String name, String url) => AiProvider(
          id: 'x',
          name: name,
          kind: 'remote',
          baseUrl: url,
        );

    test('reconnaît le preset Ollama par le port', () {
      expect(
        isOllamaProvider(
            p('Ollama (réseau local)', 'http://localhost:11434')),
        isTrue,
      );
    });

    test('reconnaît un nom ou une URL contenant ollama', () {
      expect(isOllamaProvider(p('Mon Ollama', 'http://10.0.0.5:11434')),
          isTrue);
      expect(isOllamaProvider(p('Local', 'http://ollama.local:8080')),
          isTrue);
    });

    test('ignore les autres fournisseurs', () {
      expect(isOllamaProvider(p('OpenAI', 'https://api.openai.com')),
          isFalse);
      expect(isOllamaProvider(p('Groq', 'https://api.groq.com/openai')),
          isFalse);
    });
  });

  group('isAndroidLocalhostProvider', () {
    AiProvider p(String url) => AiProvider(
          id: 'x',
          name: 'Ollama',
          kind: 'remote',
          baseUrl: url,
        );

    test('localhost + plateforme Android → vrai', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(isAndroidLocalhostProvider(p('http://localhost:11434')), isTrue);
      expect(isAndroidLocalhostProvider(p('http://127.0.0.1:11434')), isTrue);
    });

    test('adresse LAN → faux (serveur sur un autre appareil)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(isAndroidLocalhostProvider(p('http://192.168.1.42:11434')),
          isFalse);
    });

    test('localhost hors Android → faux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(isAndroidLocalhostProvider(p('http://localhost:11434')), isFalse);
    });
  });

  group('termuxRunCommandArgs', () {
    test('contient les extras requis par Termux', () {
      final args = termuxRunCommandArgs();
      expect(args['com.termux.RUN_COMMAND_PATH'], kTermuxBash);
      expect(args['com.termux.RUN_COMMAND_WORKDIR'], kTermuxHome);
      expect(args['com.termux.RUN_COMMAND_BACKGROUND'], isTrue);
      expect(
        args['com.termux.RUN_COMMAND_ARGUMENTS'],
        <String>['-c', ollamaServeCommand()],
      );
    });
  });

  group('copyToClipboard', () {
    test('échoue sans erreur si le presse-papiers est indisponible', () async {
      // Dans un test unitaire sans binding widget ni mock de canal,
      // Clipboard.setData lève MissingPluginException : on attend que la
      // fonction absorbe l'erreur et renvoie false (jamais d'exception).
      expect(await copyToClipboard('abc'), isFalse);
    });
  });
}