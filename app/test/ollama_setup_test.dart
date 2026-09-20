import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/models.dart';
import 'package:pancartplayer/core/ollama_setup.dart';

Future<OllamaHttpResult> _okServer(Uri url) async {
  if (url.path.endsWith('/api/version')) {
    return const OllamaHttpResult(200, '{"version":"0.31.1"}');
  }
  if (url.path.endsWith('/v1/models')) {
    return const OllamaHttpResult(
      200,
      '{"object":"list","data":[{"id":"qwen3:latest"},{"id":"qwen3:0.6b"}]}',
    );
  }
  return const OllamaHttpResult(404, '');
}

void main() {
  group('suggestOllamaModel', () {
    test('préfère le qwen non-latest', () {
      expect(
        suggestOllamaModel(const ['qwen3:latest', 'qwen3:0.6b']),
        'qwen3:0.6b',
      );
    });

    test('qwen non-latest au milieu', () {
      expect(
        suggestOllamaModel(const [
          'llama3.2:latest',
          'qwen2.5:0.5b',
          'llama3.2:1b',
        ]),
        'qwen2.5:0.5b',
      );
    });

    test('aucun qwen -> premier non-latest', () {
      expect(
        suggestOllamaModel(const ['llama3.2:latest', 'llama3.2:1b']),
        'llama3.2:1b',
      );
    });

    test('liste vide -> vide', () {
      expect(suggestOllamaModel(const []), '');
    });

    test('un seul modèle', () {
      expect(suggestOllamaModel(const ['qwen3:0.6b']), 'qwen3:0.6b');
    });
  });

  group('buildOllamaProvider', () {
    test('champs remplis et id stable', () {
      final p = buildOllamaProvider(
        baseUrl: 'http://127.0.0.1:11434',
        model: 'qwen3:0.6b',
      );
      expect(p.id, 'ollama_local');
      expect(p.kind, 'remote');
      expect(p.apiKey, '');
      expect(p.defaultModel, 'qwen3:0.6b');
      expect(p.baseUrl, 'http://127.0.0.1:11434');
      expect(p.isEnabled, isTrue);
      expect(p.name, 'Ollama (téléphone)');
    });

    test('nom réseau local quand hôte distant', () {
      expect(
        buildOllamaProvider(baseUrl: 'http://192.168.1.20:11434', model: 'x')
            .name,
        'Ollama (réseau local)',
      );
      expect(ollamaProviderName('http://localhost:11434'), 'Ollama (téléphone)');
    });
  });

  group('findOllamaProvider / resolveOllamaProvider', () {
    final lists = <AiProvider>[];

    test('aucun -> création', () {
      final p = resolveOllamaProvider(
        providers: lists,
        baseUrl: 'http://127.0.0.1:11434',
        model: 'qwen3:0.6b',
      );
      expect(p.id, 'ollama_local');
      lists.add(p);
    });

    test('existant -> mise à jour idempotente, nom conservé', () {
      lists[0].name = 'Mon Ollama maison';
      final p = resolveOllamaProvider(
        providers: lists,
        baseUrl: 'http://localhost:11434',
        model: 'qwen2.5:0.5b',
      );
      expect(p.id, 'ollama_local');
      expect(p.name, 'Mon Ollama maison');
      expect(p.baseUrl, 'http://localhost:11434');
      expect(p.defaultModel, 'qwen2.5:0.5b');
      expect(lists.length, 1); // jamais de doublon
    });

    test('trouve par URL/port quand le nom ne dit pas Ollama', () {
      final others = <AiProvider>[
        AiProvider(
          id: 'x',
          name: 'Serveur IA',
          kind: 'remote',
          baseUrl: 'http://192.168.1.5:11434',
          defaultModel: 'm',
        ),
      ];
      expect(findOllamaProvider(others)?.id, 'x');
    });
  });

  group('detectOllamaServer', () {
    test('serveur Ollama détecté + modèles', () async {
      final d = await detectOllamaServer(fetcher: _okServer);
      expect(d.ok, isTrue);
      expect(d.baseUrl, 'http://127.0.0.1:11434');
      expect(d.version, '0.31.1');
      expect(d.models, contains('qwen3:0.6b'));
    });

    test('port occupé par un non-Ollama', () async {
      Future<OllamaHttpResult> f(Uri url) async {
        if (url.path.endsWith('/api/version')) {
          return const OllamaHttpResult(200, '<html>Portail</html>');
        }
        return const OllamaHttpResult(200, '{"data":[]}');
      }

      final d = await detectOllamaServer(fetcher: f);
      expect(d.status, OllamaDetectStatus.notOllama);
      expect(d.ok, isFalse);
    });

    test('rien ne répond -> unreachable', () async {
      Future<OllamaHttpResult> f(Uri url) async {
        throw const OllamaProbeError(OllamaDetectStatus.unreachable);
      }

      final d = await detectOllamaServer(fetcher: f);
      expect(d.status, OllamaDetectStatus.unreachable);
      expect(d.ok, isFalse);
    });

    test('timeout -> timeout', () async {
      Future<OllamaHttpResult> f(Uri url) async {
        throw const OllamaProbeError(OllamaDetectStatus.timeout);
      }

      final d = await detectOllamaServer(fetcher: f);
      expect(d.status, OllamaDetectStatus.timeout);
    });

    test('cleartext bloqué -> cleartext', () async {
      Future<OllamaHttpResult> f(Uri url) async {
        throw const OllamaProbeError(OllamaDetectStatus.cleartext);
      }

      final d = await detectOllamaServer(fetcher: f);
      expect(d.status, OllamaDetectStatus.cleartext);
    });

    test('santé de la 2e étape : /api/version absent mais /v1/models OK',
        () async {
      const ok = '{"object":"list","data":[{"id":"qwen3:0.6b"}]}';
      Future<OllamaHttpResult> f(Uri url) async {
        if (url.path.endsWith('/api/version')) {
          return const OllamaHttpResult(404, 'not found');
        }
        if (url.path.endsWith('/v1/models')) return const OllamaHttpResult(200, ok);
        return const OllamaHttpResult(404, '');
      }

      final d = await detectOllamaServer(fetcher: f);
      expect(d.ok, isTrue);
      expect(d.models, contains('qwen3:0.6b'));
    });

    test('une exception inattendue -> unreachable (jamais d\'explosion)',
        () async {
      Future<OllamaHttpResult> f(Uri url) async => throw StateError('x');

      final d = await detectOllamaServer(fetcher: f);
      expect(d.status, OllamaDetectStatus.unreachable);
    });
  });

  group('instructions', () {
    test('étapes Termux à jour', () {
      final cmds = ollamaSetupSteps().map((s) => s.command).join('\n');
      expect(cmds, contains('pkg install -y ollama'));
      expect(cmds, contains('ollama pull qwen3:0.6b'));
      expect(cmds, contains('OLLAMA_HOST=127.0.0.1:11434 ollama serve'));
      expect(cmds, contains('allow-external-apps=true'));
      expect(ollamaSetupSteps(), isNotEmpty);
    });

    test('étapes PC + « Expose sur le réseau »', () {
      final cmds = ollamaPcSteps().map((s) => s.command).join('\n');
      expect(cmds, contains('ollama serve'));
      expect(cmds, contains('OLLAMA_HOST=0.0.0.0:11434 ollama serve'));
    });

    test('message de détection OK lisible', () {
      const d = OllamaDetection(
        status: OllamaDetectStatus.ok,
        baseUrl: 'http://127.0.0.1:11434',
        version: '0.31.1',
        models: ['qwen3:0.6b'],
      );
      expect(ollamaDetectMessage(d), contains('Ollama détecté'));
      expect(ollamaDetectMessage(d), contains('qwen3:0.6b'));
    });

    test('aide plateforme non vide', () {
      expect(platformOllamaHint().isNotEmpty, isTrue);
    });
  });
}