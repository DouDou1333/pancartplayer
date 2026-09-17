import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/catalog.dart';
import '../../core/models.dart';

class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  final Map<String, bool> _downloading = {};

  Future<void> _start(CatalogModel model) async {
    if (_downloading[model.id] == true) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Téléchargement local indisponible sur le web — utilisez un '
            'fournisseur distant (onglet « IA »).',
          ),
        ),
      );
      return;
    }
    setState(() => _downloading[model.id] = true);
    try {
      await for (final _ in ref
          .read(modelsProvider)
          .download(model)) {
        if (mounted) setState(() {});
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Téléchargement interrompu : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading[model.id] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(modelsProvider);
    final custom = models.custom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles locaux'),
        actions: [
          IconButton(
            tooltip: 'Importer un fichier GGUF de l\'appareil',
            icon: const Icon(Icons.folder_open),
            onPressed: _importLocalFile,
          ),
          IconButton(
            tooltip: 'Importer depuis Hugging Face',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _importFromHf,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _SectionLabel('Recommandés pour téléphone (RAM réduite)'),
          ...kCatalog
              .where((m) => m.recommendedFor == 'phone')
              .map((m) => _ModelTile(
                    model: m,
                    device: models.stateFor(m.id),
                    downloading: _downloading[m.id] ?? false,
                    onDownload: () => _start(m),
                  )),
          const _SectionLabel('Universels (smartphone costaud + bureau)'),
          ...kCatalog
              .where((m) => m.recommendedFor == 'all')
              .map((m) => _ModelTile(
                    model: m,
                    device: models.stateFor(m.id),
                    downloading: _downloading[m.id] ?? false,
                    onDownload: () => _start(m),
                  )),
          const _SectionLabel('Bureau (dont Ornith-9B — ton modèle)'),
          ...kCatalog
              .where((m) => m.recommendedFor == 'desktop')
              .map((m) => _ModelTile(
                    model: m,
                    device: models.stateFor(m.id),
                    downloading: _downloading[m.id] ?? false,
                    onDownload: () => _start(m),
                  )),
          if (custom.isNotEmpty) ...[
            const _SectionLabel('Modèles importés (URL Hugging Face)'),
            ...custom.map((m) => _ModelTile(
                  model: m,
                  device: models.stateFor(m.id),
                  downloading: _downloading[m.id] ?? false,
                  onDownload: () => _start(m),
                  onDelete: () => _removeCustom(m.id),
                )),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _importLocalFile() async {
    if (kIsWeb) {
      _snack('Import de fichier local indisponible sur le web — utilise '
          'l\'import par URL Hugging Face.');
      return;
    }
    const typeGroup = XTypeGroup(
      label: 'GGUF',
      extensions: ['gguf'],
    );
    String? path;
    try {
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      path = file?.path;
    } catch (e) {
      _snack('Sélecteur de fichier indisponible : $e');
      return;
    }
    if (path == null || path.isEmpty) return;
    final name = _baseName(path);
    final ok = await ref.read(modelsProvider).importPath(name, path);
    _snack(ok
        ? '« $name » importé comme modèle local — prêt dans le chat.'
        : 'Import impossible pour « $name ».');
  }

  static String _baseName(String p) => p.split(RegExp(r'[/\\]')).last;

  Future<void> _removeCustom(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce modèle importé ?'),
        content: const Text(
          'La fiche est retirée (le fichier déjà téléchargé reste sur l\'appareil).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(modelsProvider).removeCustom(id);
    }
  }

  Future<void> _importFromHf() async {
    if (kIsWeb) {
      _snack('Import local indisponible sur le web — utilise un fournisseur '
          'distant (onglet « IA »).');
      return;
    }
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer un modèle Hugging Face'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Colle l\'URL directe d\'un fichier .gguf :\n'
              'https://huggingface.co/<org>/<repo>/resolve/main/<fichier>.gguf',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL du GGUF',
                hintText: 'https://huggingface.co/…/resolve/main/….gguf',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    if (url != null && mounted) {
      await _addCustom(url);
    }
  }

  Future<void> _addCustom(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !url.toLowerCase().endsWith('.gguf')) {
      _snack('URL invalide : attends une URL …/…gguf (http/https).');
      return;
    }
    final model = CatalogModel.fromHfUrl(url: url);
    final models = ref.read(modelsProvider);
    await models.addCustom(model);
    _snack('Modèle « ${model.name} » importé — touche « Télécharger » pour le '
        'récupérer sur l\'appareil.');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: const Color(0xFF9A8CFF)),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.device,
    required this.downloading,
    required this.onDownload,
    this.onDelete,
  });

  final CatalogModel model;
  final DeviceModel? device;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isDownloaded = device?.isDownloaded == true;
    final pct = (device?.downloadProgress ?? 0).clamp(0.0, 1.0);

    return Card(
      color: const Color(0xFF1D1D2B),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isDownloaded)
                  const Icon(Icons.check_circle, color: Color(0xFF5BD27B), size: 18),
                if (downloading)
                  const Icon(Icons.downloading, color: Color(0xFF9A8CFF), size: 18),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Supprimer ce modèle importé',
                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${model.params} · ${model.quant} · ${_fmt(model.sizeMb)} Mo'
              ' · ${model.owner}/${model.file}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white12,
                color: const Color(0xFF6C4DF6),
              ),
              const SizedBox(height: 4),
              Text(
                '${(pct * 100).toStringAsFixed(0)} %',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: isDownloaded ? null : onDownload,
                    icon: Icon(
                      isDownloaded ? Icons.folder_open : Icons.download,
                      size: 18,
                    ),
                    label: Text(
                      isDownloaded
                          ? 'Prêt (${model.params})'
                          : 'Télécharger',
                    ),
                  ),
                  if (isDownloaded && model.recommendedFor == 'phone')
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'utilisable sur ce téléphone',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(int mb) => mb >= 1000
      ? (mb / 1000).toStringAsFixed(1).replaceAll('.', ',')
      : mb.toString();
}