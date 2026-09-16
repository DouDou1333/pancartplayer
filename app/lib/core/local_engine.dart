/// Moteur local : inference GGUF sur l'appareil via llama.cpp (`llamadart` 0.8.x).
///
/// API officielle (pub.dev : llamadart) :
///   LlamaEngine(LlamaBackend()) -> loadModelSource(ModelSource.parse(...))
///   -> await for (chunk in create(messages, params: GenerationParams(...)))
///
/// Ce fichier est le SEUL point d'intégration avec `llamadart`.
library;

import 'dart:async';

import 'package:llamadart/llamadart.dart';

class LocalEngineException implements Exception {
  final String message;
  LocalEngineException(this.message);
  @override
  String toString() => message;
}

class LocalEngine {
  LocalEngine._();
  static final LocalEngine instance = LocalEngine._();

  LlamaEngine? _engine;
  bool _loaded = false;
  String _loadedPath = '';

  /// Indique si l'inference locale est constructible sur la plateforme courante.
  Future<bool> isSupported() async {
    try {
      _engine ??= LlamaEngine(LlamaBackend());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Charge un GGUF situé sur l'appareil (chemin local).
  Future<void> loadModel(String path, {int contextSize = 2048}) async {
    if (_loaded && _loadedPath == path) return;
    final engine = _engine ?? LlamaEngine(LlamaBackend());
    _engine = engine;
    try {
      final source = ModelSource.parse(path);
      // ALIGN_LLAMADART : n_ctx via ModelParams si souhaité — paramètres
      // par défaut déjà raisonnables.
      await engine.loadModelSource(source);
      _loaded = true;
      _loadedPath = path;
    } on Object catch (e) {
      _loaded = false;
      throw LocalEngineException('Échec du chargement du modèle ($e).');
    }
  }

  /// Génère une réponse à partir d'une liste de messages {role, content}.
  Stream<String> complete({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) {
    final engine = _engine;
    if (engine == null || !_loaded) {
      return Stream.error(LocalEngineException('Aucun modèle chargé.'));
    }
    final chat = <LlamaChatMessage>[];
    for (final m in messages) {
      final text = (m['content'] ?? '').toString();
      final role = _mapRole(m['role'] ?? 'user');
      chat.add(LlamaChatMessage.fromText(role: role, text: text));
    }
    try {
      return engine.create(
        chat,
        params: GenerationParams(maxTokens: maxTokens),
      ).map((chunk) => chunk.choices.first.delta.content ?? '');
    } on Object catch (e) {
      return Stream.error(LocalEngineException('Échec de génération ($e).'));
    }
  }

  LlamaChatRole _mapRole(String role) {
    switch (role) {
      case 'system':
        return LlamaChatRole.system;
      case 'assistant':
        return LlamaChatRole.assistant;
      default:
        return LlamaChatRole.user;
    }
  }

  Future<void> dispose() async {
    try {
      await _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _loaded = false;
    _loadedPath = '';
  }
}