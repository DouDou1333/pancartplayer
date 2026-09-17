import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/error_messages.dart';

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
        'DioException [connectionError]: SocketException: connection failed',
      );
      expect(msg, contains('vérifie l\'URL'));
    });

    test('HTTP cleartext bloqué (Android)', () {
      final msg = friendlyErrorString(
        'HttpException: Cleartext HTTP traffic to x not permitted',
      );
      expect(msg, contains('cleartext') || contains('HTTP'));
    });

    test('erreur générique', () {
      expect(friendlyErrorString('boom'), 'Erreur : boom');
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