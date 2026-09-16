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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles locaux'),
        actions: [
          IconButton(
            tooltip: 'Rechercher sur Hugging Face',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () => _openHub(),
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _openHub() {
    // Ouvre l'annuaire GGUF : l'utilisateur peut coller un identifiant
    // custom grace à une future importation URL.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pour un modèle custom : fournissez l\'URL directe du GGUF (import URL à venir).',
        ),
      ),
    );
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
  });

  final CatalogModel model;
  final DeviceModel? device;
  final bool downloading;
  final VoidCallback onDownload;

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