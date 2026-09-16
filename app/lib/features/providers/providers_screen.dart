import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/models.dart';

class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  Future<void> _add() async {
    final ctrl = ref.read(providersProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ProviderDialog(
        presets: kProviderPresets,
        onSave: (p) async {
          await ctrl.save(p);
          Navigator.pop(ctx, true);
        },
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _edit(AiProvider p) async {
    final ctrl = ref.read(providersProvider);
    await showDialog<bool>(
      context: context,
      builder: (ctx) => _ProviderDialog(
        existing: p,
        presets: kProviderPresets,
        onSave: (np) async {
          await ctrl.save(np);
          Navigator.pop(ctx, true);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(providersProvider);
    final items = ctrl.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs d\'IA'),
        actions: [
          IconButton(
            tooltip: 'Ajouter un fournisseur',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns_outlined, size: 64, color: Colors.white24),
                  const SizedBox(height: 12),
                  const Text(
                    'Aucun fournisseur. Ajoute une API '
                    '(OpenAI, OpenRouter, Groq, Ollama, ton propre endpoint…)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une IA'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final p = items[i];
                return Card(
                  color: const Color(0xFF1D1D2B),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2A2A3C),
                      child: Icon(
                        p.kind == 'local'
                            ? Icons.phone_android
                            : Icons.cloud_outlined,
                        color: const Color(0xFF9A8CFF),
                      ),
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.kind == 'remote'
                          ? '${p.baseUrl} · ${p.defaultModel}'
                          : 'Moteur local (GGUF sur appareil)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: false,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: p.isEnabled,
                          onChanged: (v) async {
                            p.isEnabled = v;
                            await ctrl.save(p);
                          },
                        ),
                        PopupMenuButton<String>(
                          onSelected: (c) async {
                            if (c == 'edit') {
                              await _edit(p);
                            } else if (c == 'delete') {
                              await ctrl.delete(p.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ProviderDialog extends ConsumerStatefulWidget {
  const _ProviderDialog({
    this.existing,
    required this.presets,
    required this.onSave,
  });

  final AiProvider? existing;
  final List<AiProvider> presets;
  final Future<void> Function(AiProvider) onSave;

  @override
  ConsumerState<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends ConsumerState<_ProviderDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _isLocal = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _isLocal = e?.kind == 'local';
    _name = TextEditingController(text: e?.name ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _key = TextEditingController(text: e?.apiKey ?? '');
    _model = TextEditingController(
        text: e?.defaultModel.isNotEmpty == true ? e!.defaultModel : 'auto');
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _applyPreset(AiProvider preset) {
    setState(() {
      _name.text = preset.name;
      _baseUrl.text = preset.baseUrl;
      _model.text = preset.defaultModel;
      _isLocal = false;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final id = widget.existing?.id ??
        'prov_${DateTime.now().millisecondsSinceEpoch}';
    final p = AiProvider(
      id: id,
      name: _name.text.trim(),
      kind: _isLocal ? 'local' : 'remote',
      baseUrl: _baseUrl.text.trim(),
      apiKey: _key.text.trim(),
      defaultModel: _model.text.trim(),
      isEnabled: widget.existing?.isEnabled ?? true,
    );
    await widget.onSave(p);
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.existing == null;

    return AlertDialog(
      title: Text(preset ? 'Nouvelle IA' : 'Modifier ${widget.existing!.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preset) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Presets rapides',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.presets
                    .map((p) => ActionChip(
                          label: Text(p.name),
                          onPressed: () => _applyPreset(p),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            SwitchListTile(
              title: const Text('Moteur local (GGUF sur l\'appareil)'),
              value: _isLocal,
              onChanged: (v) => setState(() => _isLocal = v),
              contentPadding: EdgeInsets.zero,
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            if (!_isLocal) ...[
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'URL de base',
                  hintText: 'https://api.openai.com',
                ),
              ),
              TextField(
                controller: _key,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Clef API'),
              ),
            ],
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Modèle par défaut',
                hintText: 'auto',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}