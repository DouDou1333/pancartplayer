/// Fournisseurs d'état (Riverpod) pour toute l'application.
library;

import 'dart:async';
import 'dart:io' show Directory;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage.dart';
import 'models.dart';
import 'catalog.dart';

/// Accès global à la couche stockage (initialisée dans `main()`).
final appStoreProvider = Provider<AppStore>((ref) => AppStore.instance);

// ---------------------------------------------------------------------------
// Conversations
// ---------------------------------------------------------------------------
class ChatsController extends ChangeNotifier {
  ChatsController(this._store) {
    reload();
  }

  final AppStore _store;
  List<Conversation> _items = [];
  String? _selectedId;

  List<Conversation> get items => _items;
  Conversation? get selected => _selected(_selectedId);

  Conversation? _selected(String? id) {
    if (id == null) return null;
    for (final c in _items) {
      if (c.id == id) return c;
    }
    return null;
  }

  void reload() {
    _items = _store.conversations();
    if (_selectedId != null &&
        _selected(_selectedId) == null) {
      _selectedId = null;
    }
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  Conversation create({required String providerId, required String modelId}) {
    final conv = Conversation(
      id: 'conv_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Nouvelle conversation',
      providerId: providerId,
      modelId: modelId,
      createdAt: DateTime.now(),
    );
    _items.insert(0, conv);
    _selectedId = conv.id;
    notifyListeners();
    return conv;
  }

  Future<void> delete(String id) async {
    await _store.deleteConversation(id);
    reload();
  }

  void push(Conversation c) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id == c.id) {
        _items[i] = c;
        notifyListeners();
        return;
      }
    }
  }
}

final chatsProvider =
    ChangeNotifierProvider<ChatsController>((ref) => ChatsController(ref.watch(appStoreProvider)));

// ---------------------------------------------------------------------------
// Fournisseurs d'IA
// ---------------------------------------------------------------------------
final kProviderPresets = <AiProvider>[
  AiProvider(
    id: 'preset_openai',
    name: 'OpenAI',
    kind: 'remote',
    baseUrl: 'https://api.openai.com',
    defaultModel: 'gpt-4o-mini',
  ),
  AiProvider(
    id: 'preset_openrouter',
    name: 'OpenRouter',
    kind: 'remote',
    baseUrl: 'https://openrouter.ai/api',
    defaultModel: 'openrouter/auto',
  ),
  AiProvider(
    id: 'preset_groq',
    name: 'Groq',
    kind: 'remote',
    baseUrl: 'https://api.groq.com/openai',
    defaultModel: 'llama-3.3-70b-versatile',
  ),
  AiProvider(
    id: 'preset_ollama',
    name: 'Ollama (réseau local)',
    kind: 'remote',
    baseUrl: 'http://localhost:11434',
    defaultModel: 'llama3',
  ),
];

class ProvidersController extends ChangeNotifier {
  ProvidersController(this._store) {
    reload();
  }

  final AppStore _store;
  List<AiProvider> _items = [];
  List<AiProvider> get items => _items;

  void reload() {
    _items = _store.providers();
    notifyListeners();
  }

  Future<void> save(AiProvider p) async {
    await _store.saveProvider(p);
    reload();
  }

  Future<void> delete(String id) async {
    await _store.deleteProvider(id);
    reload();
  }
}

final providersProvider = ChangeNotifierProvider<ProvidersController>(
    (ref) => ProvidersController(ref.watch(appStoreProvider)));

// ---------------------------------------------------------------------------
// Modèles locaux + catalogue
// ---------------------------------------------------------------------------
class ModelsController extends ChangeNotifier {
  ModelsController(this._store) {
    reload();
  }

  final AppStore _store;
  List<DeviceModel> _device = [];
  List<CatalogModel> _custom = [];

  List<DeviceModel> get device => _device;

  List<CatalogModel> get custom => _custom;

  /// Catalogue complet : modèles embarqués + modèles importés.
  List<CatalogModel> get allCatalog => <CatalogModel>[...kCatalog, ..._custom];

  /// Résout un modèle (catalogue embarqué ou importé) par son id.
  CatalogModel? catalogFor(String id) => catalogByIdOrCustom(id, _custom);

  /// Résout un modèle importé par le nom de fichier (résultat d'ablitération).
  CatalogModel? catalogForFile(String file) {
    for (final m in _custom) {
      if (m.file == file || m.name == file) return m;
    }
    return null;
  }

  void reload() {
    _custom = _store.customModels();
    final list = _store.deviceModels();
    for (final d in list) {
      d.catalog = catalogByIdOrCustom(d.catalogId, _custom);
    }
    _device = list;
    notifyListeners();
  }

  /// Ajoute un modèle importé (URL Hugging Face) puis le recharger.
  Future<void> addCustom(CatalogModel model) async {
    await _store.saveCustomModel(model);
    reload();
  }

  Future<void> removeCustom(String id) async {
    await _store.deleteCustomModel(id);
    reload();
  }

  DeviceModel? stateFor(String catalogId) {
    for (final d in _device) {
      if (d.catalogId == catalogId) return d;
    }
    return null;
  }

  /// Démarre un téléchargement (flux de progression en temps réel).
  Stream<double> download(CatalogModel model) async* {
    var d = stateFor(model.id);
    if (d == null) {
      d = DeviceModel(catalogId: model.id);
      _device.add(d);
    }
    d.isDownloading = true;
    d.downloadProgress = 0;
    notifyListeners();

    final destination = p.join(await modelsDir(), model.file);
    final progress = StreamController<double>();
    final done = Completer<void>();
    var failed = false;

    try {
      Dio()
          .download(model.downloadUrl(), destination,
              deleteOnError: true,
              onReceiveProgress: (received, total) {
                if (total > 0) progress.add(received / total);
              })
          .then((_) {
        if (!done.isCompleted) done.complete();
      }).catchError((Object e) {
        failed = true;
        if (!done.isCompleted) done.completeError(e);
      });

      done.future.then(
        (_) => progress.close(),
        onError: (_) => progress.close(),
      );

      var last = 0.0;
      await for (final pct in progress.stream) {
        d.downloadProgress = pct;
        if ((pct - last).abs() >= 0.02 || pct >= 1.0) {
          last = pct;
          notifyListeners();
        }
        yield pct;
      }
      await done.future;
    } on Object {
      rethrow;
    } finally {
      await progress.close();
      d.isDownloading = false;
      d.isDownloaded = !failed;
      d.localPath = destination;
      await _store.saveDeviceModel(d);
      notifyListeners();
    }
  }

  /// Marque un modèle comme importé depuis un chemin local (ex: resultat
  /// d'une abliteration déposée sur l'appareil). Si le nom ne correspond à
  /// aucun modèle connu, on crée un modèle custom « fichier ».
  Future<bool> importPath(String targetFile, String localPath) async {
    var model = catalogById(targetFile) ?? catalogForFile(targetFile);
    if (model == null) {
      model = CatalogModel.fromFilePath(targetFile.split('/').last);
      await _store.saveCustomModel(model);
    }
    final d = stateFor(model.id) ?? DeviceModel(catalogId: model.id);
    d.isDownloaded = true;
    d.isDownloading = false;
    d.localPath = localPath;
    await _store.saveDeviceModel(d);
    reload();
    return true;
  }
}

final modelsProvider =
    ChangeNotifierProvider<ModelsController>((ref) => ModelsController(ref.watch(appStoreProvider)));

// ---------------------------------------------------------------------------
// Jobs d'ablitération
// ---------------------------------------------------------------------------
class AblitController extends ChangeNotifier {
  AblitController(this._store) {
    reload();
  }

  final AppStore _store;
  List<AblitJob> _jobs = [];
  List<AblitJob> get jobs => _jobs;

  void reload() {
    _jobs = _store.jobs()..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0) - (a.createdAt?.millisecondsSinceEpoch ?? 0));
    notifyListeners();
  }

  Future<AblitJob> add(String sourceName) async {
    final job = AblitJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}',
      sourceModelName: sourceName,
      createdAt: DateTime.now(),
    );
    await _store.saveJob(job);
    reload();
    return job;
  }

  Future<void> update(AblitJob j) async {
    await _store.saveJob(j);
    reload();
  }
}

final ablitControllerProvider =
    ChangeNotifierProvider<AblitController>((ref) => AblitController(ref.watch(appStoreProvider)));

// ---------------------------------------------------------------------------
// Téléchargement avec progression (dio, tous supports)
// ---------------------------------------------------------------------------

/// Répertoire racine des modèles GGUF sur l'appareil.
/// Sur le web, les modèles locaux ne sont pas téléchargés sur disque :
/// on renvoie une chaîne vide (fonctionnalité désactivée dans l'UI).
Future<String> modelsDir() async {
  if (kIsWeb) return '';
  try {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  } catch (_) {
    return '';
  }
}