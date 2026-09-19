/// Client IA distant compatible OpenAI — streaming + non-streaming.
///
/// Compatible avec : OpenAI, OpenRouter, Groq, vLLM, Ollama, LM Studio,
/// ou tout endpoint respectant `/v1/chat/completions`.
///
/// Sur le web, le streaming SSE n'est pas garanti ; fallback non-stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class RemoteClient {
  RemoteClient({required this.baseUrl, required this.apiKey, this.timeout = const Duration(seconds: 120)});

  final String baseUrl;
  final String apiKey;
  final Duration timeout;

  String _endpoint(String path) {
    String u = baseUrl.trimRight();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.endsWith('/v1')) u = '$u/v1';
    return '$u$path';
  }

  Map<String, dynamic> _headers() {
    final h = <String, dynamic>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) h['Authorization'] = 'Bearer $apiKey';
    return h;
  }

  /// Envoie un chat completions (non streamé) et renvoie le texte complet.
  Future<String> reply({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: _headers(),
    ));
    final response = await dio.post(
      _endpoint('/chat/completions'),
      data: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': false,
      }),
    );
    final data = response.data as Map<String, dynamic>;
    return data['choices'][0]['message']['content'] as String? ?? '';
  }

  /// Répond en streaming. Renvoie un `Stream<String>` de tokens.
  /// Si SSE échoue (web), re-tombe en mode non streamé.
  Stream<String> streamReply({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: _headers(),
    ));
    try {
      final response = await dio.post<ResponseBody>(
        _endpoint('/chat/completions'),
        data: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true,
        }),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
      final decoder = SseDecoder();
      await for (final chunk in response.data!.stream) {
        for (final payload in decoder.add(chunk)) {
          try {
            final m = jsonDecode(payload) as Map<String, dynamic>;
            final choices = m['choices'] as List? ?? const [];
            if (choices.isNotEmpty) {
              final delta = (choices.first as Map)['delta'];
              if (delta is Map && delta['content'] != null) {
                yield delta['content'] as String;
              }
            }
          } catch (_) {
            // payload JSON malformé → ignoré (le flux continue)
          }
        }
        if (decoder.isComplete) return;
      }
    } on DioException catch (e) {
      if (!isRetryableForNonStream(e)) rethrow;
      // Fallback non-stream (web notamment)
      final fallback = await reply(
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      yield fallback;
    }
  }
}

/// Vrai si un échec de flux mérite une relance en non-streamé (web).
/// Les réponses HTTP réelles (4xx/5xx) ne sont pas des fautes du transport :
/// on les remonte telles quelles au lieu de déclencher un second appel voué
/// au même échec et qui masque le message d'erreur (ex. Ollama : modèle
/// introuvable → 404).
bool isRetryableForNonStream(Object e) {
  if (e is! DioException) return true;
  return e.type != DioExceptionType.badResponse &&
      e.type != DioExceptionType.cancel;
}

/// Décodeur SSE robuste : tamponne les chunks réseau, découpe aux fins de
/// ligne et renvoie les payloads `data:` (événements `[DONE]` exclus).
///
/// Sans ce tampon, un événement scindé entre deux paquets TCP (fréquent sur
/// mobile) serait perdu ou corrompu, et un caractère UTF-8 multi-octets coupé
/// ferait lever une erreur de décodage qui interromprait le chat.
class SseDecoder {
  final Utf8Decoder _utf8 = const Utf8Decoder(allowMalformed: true);
  String _pending = '';
  bool _complete = false;

  bool get isComplete => _complete;

  /// Ajoute un chunk de bytes bruts ; renvoie les payloads `data:` terminés.
  List<String> add(List<int> chunk) {
    if (_complete) return const [];
    _pending += _utf8.convert(chunk);
    final events = <String>[];
    while (true) {
      final nl = _pending.indexOf('\n');
      if (nl < 0) break; // ligne incomplète → attendre le chunk suivant
      final line = _pending.substring(0, nl);
      _pending = _pending.substring(nl + 1);
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trimLeft();
      if (payload == '[DONE]') {
        _complete = true;
      } else {
        events.add(payload);
      }
    }
    return events;
  }
}