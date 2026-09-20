import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/error_messages.dart';

DioException _dioStatus(int statusCode, [Object? data]) {
  final opts = RequestOptions(path: 'http://exemple.local/v1/chat/completions');
  return DioException(
    type: DioExceptionType.badResponse,
    requestOptions: opts,
    response: Response<dynamic>(
      requestOptions: opts,
      statusCode: statusCode,
      data: data,
    ),
  );
}

void main() {
  group('friendlyErrorString', () {
    test('EPERM/errno 1 -> réseau bloqué', () {
      final msg = friendlyErrorString(
        'SocketException: Operation not permitted, errno=1, localhost:11434',
      );
      expect(msg, contains('Réseau bloqué'));
      expect(msg, contains('Android'));
    });

    test('SocketException -> connexion impossible', () {
      final msg = friendlyErrorString(
        'SocketException: Connection refused, host=192.168.1.42, port=11434',
      );
      expect(msg, contains('Connexion impossible'));
    });

    test('DioException connection -> fournisseur injoignable', () {
      final msg = friendlyErrorString(
        'DioException [connection error]: failed to connect to '
        'https://api.exemple.com:443',
      );
      expect(msg, contains('vérifie l\'URL'));
    });

    test('HTTP cleartext bloqué (Android)', () {
      final msg = friendlyErrorString(
        'HttpException: Cleartext HTTP traffic to x not permitted',
      );
      expect(msg, anyOf(contains('cleartext'), contains('HTTP')));
    });

    test('erreur générique', () {
      expect(friendlyErrorString('boom'), 'Erreur : boom');
    });

    test('404 Ollama : modèle manquant -> conseille ollama pull', () {
      final e = _dioStatus(404, {
        'error': "model 'llama3' not found, try pulling it first",
      });
      final msg = friendlyErrorString(e);
      expect(msg, contains('ollama pull llama3'));
      expect(msg, contains('qwen3:0.6b'));
      expect(msg, isNot(contains('Erreur :')));
    });

    test('404 générique -> mauvaise adresse / endpoint', () {
      final msg = friendlyErrorString(_dioStatus(404, 'not found'));
      expect(msg, contains('404'));
      expect(msg, contains('/v1'));
      expect(msg, isNot(contains('Erreur :')));
    });

    test('3xx -> redirection expliquée', () {
      final msg = friendlyErrorString(_dioStatus(301, 'redirect'));
      expect(msg, contains('Redirection HTTP (301)'));
      expect(msg, contains('https://'));
      expect(msg, isNot(contains('Erreur :')));
    });

    test('4xx -> « Réponse HTTP » avec corps du serveur', () {
      final msg = friendlyErrorString(_dioStatus(403, {'error': 'Invalid key'}));
      expect(msg, contains('Réponse HTTP 403'));
      expect(msg, contains('Invalid key'));
      expect(msg, isNot(contains('Erreur :')));
    });

    test('5xx -> « Réponse HTTP » même avec corps brut tronqué', () {
      final msg = friendlyErrorString(_dioStatus(500, 'boom'));
      expect(msg, contains('Réponse HTTP 500'));
      expect(msg, isNot(contains('Erreur :')));
    });
  });

  group('isLocalhostBaseUrl', () {
    test('localhost / 127.0.0.1 détectés', () {
      expect(isLocalhostBaseUrl('http://localhost:11434'), isTrue);
      expect(isLocalhostBaseUrl('http://127.0.0.1:8080'), isTrue);
      expect(isLocalhostBaseUrl('http://192.168.1.42:11434'), isFalse);
      expect(isLocalhostBaseUrl('https://api.openai.com'), isFalse);
      expect(isLocalhostBaseUrl('http://10.0.0.3'), isFalse);
    });
  });

  group('localhostMobileHint', () {
    test('contient le remplacement et OLLAMA_HOST', () {
      final hint = localhostMobileHint('http://localhost:11434');
      expect(hint, contains('http://<IP-du-PC>:11434'));
      expect(hint, contains('OLLAMA_HOST=0.0.0.0'));
    });
  });
}