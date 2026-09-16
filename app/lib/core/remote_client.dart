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
        options: Options(responseType: ResponseType.stream),
      );
      await for (final chunk in response.data!.stream) {
        final raw = utf8.decode(chunk);
        for (final line in raw.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final json = line.substring(6).trim();
          if (json == '[DONE]') return;
          try {
            final m = jsonDecode(json) as Map<String, dynamic>;
            final choices = m['choices'] as List? ?? const [];
            if (choices.isNotEmpty) {
              final delta = choices.first['delta'];
              if (delta != null && delta['content'] != null) {
                yield delta['content'] as String;
              }
            }
          } catch (_) {
            // chunk mal formé → ignoré
          }
        }
      }
    } on DioException catch (_) {
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