/// Modèles de données PancartPlayer (sérialisés en JSON, stockage Hive).
///
/// Toutes les classes stockables disposent d'une conversion `Map`/`JSON`
/// afin de ne dépendre d'aucun générateur de code (robuste, zéro codegen).
library;

/// Un fournisseur d'IA : soit un moteur local, soit une API distante
/// compatible OpenAI (URL + clé).
class AiProvider {
  AiProvider({
    required this.id,
    required this.name,
    required this.kind,
    this.baseUrl = '',
    this.apiKey = '',
    this.defaultModel = '',
    this.isEnabled = true,
  });

  final String id;
  String name;
  final String kind; // 'local' | 'remote'
  String baseUrl;
  String apiKey;
  String defaultModel;
  bool isEnabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'defaultModel': defaultModel,
        'isEnabled': isEnabled,
      };

  factory AiProvider.fromJson(Map<String, dynamic> json) => AiProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Provider',
        kind: json['kind'] as String? ?? 'remote',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        defaultModel: json['defaultModel'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}

/// Un modèle GGUF téléchargeable/catalogue.
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.name,
    required this.owner,
    required this.repo,
    required this.file,
    this.params = '?',
    this.quant = 'Q4_K_M',
    this.sizeMb = 0,
    this.recommendedFor = 'all',
    this.tags = const [],
    this.hfUrl = true,
  });

  final String id;
  final String name;
  final String owner; // auteur HF (ex: ornith-ai)
  final String repo; // identifiant complet du repo HF
  final String file; // nom précis du GGUF dans le repo
  final String params;
  final String quant;
  final int sizeMb;
  final String recommendedFor; // 'phone' | 'desktop' | 'all'
  final List<String> tags;
  final bool hfUrl; // true => construit l'URL HF ; false => repo/file = URL directe

  String downloadUrl() => hfUrl
      ? 'https://huggingface.co/$repo/resolve/main/$file'
      : repo;

  /// Construit un modèle importé à partir d'une URL Hugging Face (resolve ou
  /// URL directe d'un fichier .gguf). `repo` stocke alors l'URL complète
  /// (`hfUrl = false`), et `downloadUrl()` renvoie directement cette URL.
  factory CatalogModel.fromHfUrl({
    required String url,
    String? name,
    int sizeMb = 0,
  }) {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    final segs = (uri?.pathSegments ?? const <String>[])
        .where((s) => s.isNotEmpty)
        .toList();

    var owner = '';
    var file = '';
    if (clean.toLowerCase().contains('huggingface.co') && segs.length >= 2) {
      owner = segs[0];
      if (segs.length >= 4 && segs[2].toLowerCase() == 'resolve') {
        file = segs.sublist(4).join('/');
      } else {
        file = segs.last;
      }
    } else {
      file = segs.isEmpty ? '' : segs.last;
    }
    if (file.isEmpty) file = clean;

    final fileName = file.split('/').last;
    final base = fileName
        .toLowerCase()
        .replaceFirst(RegExp(r'\.gguf$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    return CatalogModel(
      id: 'custom-${base.isEmpty ? 'modele' : base}',
      name: name == null || name.trim().isEmpty
          ? (file.split('/').last.isEmpty ? 'Modèle importé' : file.split('/').last)
          : name.trim(),
      owner: owner,
      repo: clean,
      file: file,
      params: 'importé',
      quant: '?',
      sizeMb: sizeMb,
      recommendedFor: 'all',
      tags: const ['importé', 'custom'],
      hfUrl: false,
    );
  }

  /// Modèle issu d'un fichier GGUF placé sur l'appareil (ex: résultat
  /// d'une ablitération). `downloadUrl()` renvoie `repo` mais le modèle est
  /// toujours obtenu via son chemin local.
  factory CatalogModel.fromFilePath(String fileName, {int sizeMb = 0}) {
    final base = fileName
        .toLowerCase()
        .replaceFirst(RegExp(r'\.gguf$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return CatalogModel(
      id: 'custom-${base.isEmpty ? 'fichier' : base}',
      name: fileName,
      owner: 'local',
      repo: 'import local',
      file: fileName,
      params: 'importé',
      quant: '?',
      sizeMb: sizeMb,
      recommendedFor: 'all',
      tags: const ['importé', 'fichier'],
      hfUrl: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner': owner,
        'repo': repo,
        'file': file,
        'params': params,
        'quant': quant,
        'sizeMb': sizeMb,
        'recommendedFor': recommendedFor,
        'tags': tags,
        'hfUrl': hfUrl,
      };

  factory CatalogModel.fromJson(Map<String, dynamic> json) => CatalogModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        owner: json['owner'] as String? ?? '',
        repo: json['repo'] as String? ?? '',
        file: json['file'] as String? ?? '',
        params: json['params'] as String? ?? '?',
        quant: json['quant'] as String? ?? 'Q4_K_M',
        sizeMb: (json['sizeMb'] as num?)?.toInt() ?? 0,
        recommendedFor: json['recommendedFor'] as String? ?? 'all',
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        hfUrl: json['hfUrl'] as bool? ?? true,
      );
}

/// État de téléchargement / présence d'un modèle sur l'appareil.
class DeviceModel {
  DeviceModel({
    required this.catalogId,
    this.localPath = '',
    this.downloadProgress = 0.0,
    this.isDownloading = false,
    this.isDownloaded = false,
  });

  final String catalogId;
  String localPath;
  double downloadProgress;
  bool isDownloading;
  bool isDownloaded;

  CatalogModel? catalog;

  Map<String, dynamic> toJson() => {
        'catalogId': catalogId,
        'localPath': localPath,
        'downloadProgress': downloadProgress,
        'isDownloading': isDownloading,
        'isDownloaded': isDownloaded,
      };

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
        catalogId: json['catalogId'] as String? ?? '',
        localPath: json['localPath'] as String? ?? '',
        downloadProgress: (json['downloadProgress'] as num?)?.toDouble() ?? 0,
        isDownloading: json['isDownloading'] as bool? ?? false,
        isDownloaded: json['isDownloaded'] as bool? ?? false,
      );
}

/// Un message dans une conversation.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
    this.isStreaming = false,
    this.error = '',
  });

  final String role; // 'user' | 'assistant' | 'system'
  String content;
  DateTime? timestamp;
  bool isStreaming;
  String error;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp?.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
      );
}

/// Une conversation : titre, modèle/provider ciblé, historique.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.providerId,
    required this.modelId,
    this.createdAt,
    List<ChatMessage>? messages,
  }) : messages = messages ?? <ChatMessage>[];

  final String id;
  String title;
  String providerId;
  String modelId;
  DateTime? createdAt;
  List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'providerId': providerId,
        'modelId': modelId,
        'createdAt': createdAt?.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Nouvelle conversation',
        providerId: json['providerId'] as String? ?? '',
        modelId: json['modelId'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        messages: (json['messages'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String preview() {
    if (messages.isEmpty) return 'Aucun message';
    for (final m in messages.reversed) {
      if (m.content.trim().isNotEmpty) {
        final text = m.content.trim().replaceAll('\n', ' ');
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
      }
    }
    return 'Aucun message';
  }
}

/// États d'un job d'ablitération.
enum AblitState { pending, running, done, failed }

/// Un job d'ablitération suivi depuis l'application.
class AblitJob {
  AblitJob({
    required this.id,
    required this.sourceModelName,
    this.state = AblitState.pending,
    this.step = '',
    this.log = '',
    this.outputPath = '',
    this.createdAt,
  });

  final String id;
  final String sourceModelName;
  AblitState state;
  String step;
  String log;
  String outputPath;
  DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceModelName': sourceModelName,
        'state': state.index,
        'step': step,
        'log': log,
        'outputPath': outputPath,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory AblitJob.fromJson(Map<String, dynamic> json) => AblitJob(
        id: json['id'] as String? ?? '',
        sourceModelName: json['sourceModelName'] as String? ?? '',
        state: AblitState.values[
            (json['state'] as num?)?.toInt() ?? AblitState.pending.index],
        step: json['step'] as String? ?? '',
        log: json['log'] as String? ?? '',
        outputPath: json['outputPath'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  AblitJob copyWith({AblitState? state, String? step, String? log}) =>
      AblitJob(
        id: id,
        sourceModelName: sourceModelName,
        state: state ?? this.state,
        step: step ?? this.step,
        log: log ?? this.log,
        outputPath: outputPath,
        createdAt: createdAt,
      );
}