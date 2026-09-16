/// Couche de stockage robuste de PancartPlayer.
///
/// - shared_preferences (JSON) : fonctionnel sur toutes les plateformes
///   (Android, iOS, Linux, macOS, Windows, Web).
/// - flutter_secure_storage : clefs API chiffrées (natif) ; repli web.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class AppStore {
  AppStore._();

  static const _conversations = 'pp/conversations/';
  static const _providers = 'pp/providers/';
  static const _models = 'pp/models/';
  static const _jobs = 'pp/jobs/';

  late SharedPreferences _prefs;
  late final FlutterSecureStorage _secure;

  static final AppStore instance = AppStore._();

  /// À appeler une fois au démarrage avant tout accès.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  T? _read<T>(String prefix, String id) {
    final raw = _prefs.getString(prefix + id);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String prefix, String id, Object value) =>
      _prefs.setString(prefix + id, jsonEncode(value));

  Future<void> _remove(String prefix, String id) =>
      _prefs.remove(prefix + id);

  List<T> _list<T>(String prefix, T Function(Map<String, dynamic>) fromJson) {
    final keys = _prefs.getKeys()
        .where((k) => k.startsWith(prefix) && k.length > prefix.length);
    final out = <T>[];
    for (final k in keys) {
      final v = _read<Map<String, dynamic>>(prefix, k.substring(prefix.length));
      if (v != null) {
        try {
          out.add(fromJson(v));
        } catch (_) {
          // entrée corrompue → ignorée
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------
  List<Conversation> conversations() {
    final out = _list<Conversation>(
        _conversations, (m) => Conversation.fromJson(m))
      ..sort((a, b) =>
          (b.createdAt?.millisecondsSinceEpoch ?? 0) -
          (a.createdAt?.millisecondsSinceEpoch ?? 0));
    return out;
  }

  Conversation? conversation(String id) {
    final m = _read<Map<String, dynamic>>(_conversations, id);
    return m == null ? null : Conversation.fromJson(m);
  }

  Future<void> saveConversation(Conversation c) =>
      _write(_conversations, c.id, c.toJson());

  Future<void> deleteConversation(String id) =>
      _remove(_conversations, id);

  // ---------------------------------------------------------------------
  // Providers
  // ---------------------------------------------------------------------
  List<AiProvider> providers() =>
      _list<AiProvider>(_providers, (m) => AiProvider.fromJson(m));

  AiProvider? provider(String id) {
    final m = _read<Map<String, dynamic>>(_providers, id);
    return m == null ? null : AiProvider.fromJson(m);
  }

  Future<void> saveProvider(AiProvider p) async {
    await _write(_providers, p.id, p.toJson());
    await _writeKey(p.id, p.apiKey);
  }

  Future<void> deleteProvider(String id) async {
    await _remove(_providers, id);
    await _removeKey(id);
  }

  // ---------------------------------------------------------------------
  // Clefs API (chiffrées sur natif, prefs en dernier recours web)
  // ---------------------------------------------------------------------

  Future<void> _writeKey(String providerId, String key) async {
    if (key.isEmpty) return;
    if (kIsWeb) {
      await _prefs.setString('pp/keys/$providerId', key);
      return;
    }
    try {
      await _secure.write(key: 'key_$providerId', value: key);
    } catch (_) {
      await _prefs.setString('pp/keys/$providerId', key);
    }
  }

  Future<void> _removeKey(String providerId) async {
    await _prefs.remove('pp/keys/$providerId');
    try {
      await _secure.delete(key: 'key_$providerId');
    } catch (_) {}
  }

  /// Recharge une clef API stockée de façon sécurisée.
  Future<String> readKey(String providerId) async {
    if (!kIsWeb) {
      try {
        final k = await _secure.read(key: 'key_$providerId');
        if (k != null && k.isNotEmpty) return k;
      } catch (_) {}
    }
    return _prefs.getString('pp/keys/$providerId') ?? '';
  }

  // ---------------------------------------------------------------------
  // Modèles sur l'appareil
  // ---------------------------------------------------------------------
  List<DeviceModel> deviceModels() =>
      _list<DeviceModel>(_models, (m) => DeviceModel.fromJson(m));

  DeviceModel? deviceModel(String catalogId) {
    final m = _read<Map<String, dynamic>>(_models, catalogId);
    return m == null ? null : DeviceModel.fromJson(m);
  }

  Future<void> saveDeviceModel(DeviceModel m) =>
      _write(_models, m.catalogId, m.toJson());

  // ---------------------------------------------------------------------
  // Jobs d'ablitération
  // ---------------------------------------------------------------------
  List<AblitJob> jobs() =>
      _list<AblitJob>(_jobs, (m) => AblitJob.fromJson(m));

  Future<void> saveJob(AblitJob j) => _write(_jobs, j.id, j.toJson());

  // ---------------------------------------------------------------------
  // Réglages
  // ---------------------------------------------------------------------
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  String getString(String key, [String dflt = '']) => _prefs.getString(key) ?? dflt;

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  bool getBool(String key, [bool dflt = false]) => _prefs.getBool(key) ?? dflt;

  Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);

  double getDouble(String key, [double dflt = 1.0]) => _prefs.getDouble(key) ?? dflt;
}