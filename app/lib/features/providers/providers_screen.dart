import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/error_messages.dart';
import '../../core/models.dart';
import '../../core/ollama_launcher.dart';
import '../../core/ollama_setup.dart';
import '../../core/provider_probe.dart';

class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  bool _starting = false;

  AiProvider? _ollamaProvider(List<AiProvider> items) {
    for (final p in items) {
      if (isOllamaProvider(p)) return p;
    }
    return null;
  }

  Future<void> _startOllama(AiProvider p) async {
    setState(() => _starting = true);
    try {
      final r = await startOllama(p);
      if (!mounted) return;
      await _showResult(r);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _showResult(OllamaStartResult r) async {
    final okStatus = r.status != OllamaStartStatus.instructions;
    var copied = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                okStatus ? Icons.bolt : Icons.info_outline,
                color: okStatus
                    ? const Color(0xFF5BD27B)
                    : const Color(0xFF9A8CFF),
              ),
              const SizedBox(width: 8),
              Text(okStatus ? 'Ollama' : 'Ollama à lancer'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(r.message),
                if (r.command != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    r.command!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (r.command != null)
              TextButton.icon(
                onPressed: () async {
                  final ok = await copyToClipboard(r.command!);
                  if (ctx.mounted) setDialogState(() => copied = ok);
                },
                icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
                label: Text(copied ? 'Copié ✓' : 'Copier la commande'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

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

  /// Configurateur « Ollama automatiquement » : détecte le serveur local,
  /// remplit URL + modèle, puis enregistre le fournisseur (création ou
  /// mise à jour idempotente). Fonctionne sur toutes les plateformes.
  Future<void> _configureOllama() async {
    final ctrl = ref.read(providersProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OllamaSetupDialog(
        providers: ctrl.items,
        onSave: (baseUrl, model) async {
          final p = resolveOllamaProvider(
            providers: ctrl.items,
            baseUrl: baseUrl,
            model: model,
          );
          await ctrl.save(p);
          return p;
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fournisseur Ollama configuré ✓ — va discuter !'),
        ),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(providersProvider);
    final items = ctrl.items;
    final ollama = _ollamaProvider(items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs d\'IA'),
        actions: [
          if (ollama != null)
            IconButton(
              tooltip: 'Démarrer Ollama',
              icon: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              onPressed: _starting ? null : () => _startOllama(ollama),
            ),
          if (ollama == null)
            IconButton(
              tooltip: 'Configurer Ollama automatiquement',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _configureOllama,
            ),
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
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _configureOllama,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Configurer Ollama automatiquement'),
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
                            } else if (c == 'configure') {
                              await _configureOllama();
                            } else if (c == 'start') {
                              await _startOllama(p);
                            }
                          },
                          itemBuilder: (_) => [
                            if (isOllamaProvider(p))
                              const PopupMenuItem(
                                value: 'configure',
                                child: Text('Configurer automatiquement…'),
                              ),
                            if (isOllamaProvider(p))
                              const PopupMenuItem(
                                value: 'start',
                                child: Text('Démarrer Ollama'),
                              ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Modifier'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
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
  bool _testing = false;
  String? _testResult;

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

  Future<void> _testConnection() async {
    final url = _baseUrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await probeProviderUrl(url, apiKey: _key.text.trim());
      if (!mounted) return;
      setState(() => _testResult = r.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  static bool _isLocalhostUrl(String s) {
    final u = Uri.tryParse(s.trim());
    final host = u?.host.isEmpty == false ? u!.host : s.trim().toLowerCase();
    return host == 'localhost' || host == '127.0.0.1';
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
              Row(
                children: [
                  if (_testing)
                    const Text('Test en cours…',
                        style: TextStyle(color: Colors.white54, fontSize: 12))
                  else
                    TextButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(Icons.network_check, size: 16),
                      label: const Text('Tester la connexion'),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: (_testResult ?? '').startsWith('Fournisseur joignable')
                            ? const Color(0xFF5BD27B)
                            : const Color(0xFFFFB04A),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isLocalhostUrl(_baseUrl.text))
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Sur un téléphone, « localhost » désigne le téléphone lui-même : ce fournisseur ne joindra un Ollama du PC que sur ordinateur.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
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

/// Configurateur « Ollama automatiquement ».
///
/// Détecte le serveur local (sonde uniquement cet appareil), remplit l'URL et
/// le modèle, puis enregistre le fournisseur — sans jamais dupliquer ni
/// écraser le nom d'un fournisseur Ollama existant. En cas d'échec : étapes à
/// jour à copier (Termux sur Android, PC ailleurs) + possibilité de renseigner
/// manuellement (ex. IP d'un Ollama sur le Wi-Fi).
class _OllamaSetupDialog extends ConsumerStatefulWidget {
  const _OllamaSetupDialog({
    required this.providers,
    required this.onSave,
  });

  final List<AiProvider> providers;
  final Future<AiProvider> Function(String baseUrl, String model) onSave;

  @override
  ConsumerState<_OllamaSetupDialog> createState() => _OllamaSetupDialogState();
}

class _OllamaSetupDialogState extends ConsumerState<_OllamaSetupDialog> {
  late final TextEditingController _baseCtrl;
  final TextEditingController _modelCtrl = TextEditingController();
  bool _detecting = true;
  OllamaDetection? _detection;
  bool _saving = false;
  bool _launching = false;
  String? _info;
  String? _copied;

  @override
  void initState() {
    super.initState();
    _baseCtrl = TextEditingController(text: kOllamaLocalBaseUrl);
    _detect();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _detection = null;
      _info = null;
    });
    final d = await detectOllamaServer();
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _detection = d;
      if (d.baseUrl != null && d.baseUrl!.isNotEmpty) {
        _baseCtrl.text = d.baseUrl!;
      }
      final suggested = suggestOllamaModel(d.models);
      if (suggested.isNotEmpty && _modelCtrl.text.trim().isEmpty) {
        _modelCtrl.text = suggested;
      }
    });
  }

  Future<void> _launch() async {
    setState(() {
      _launching = true;
      _info = null;
    });
    try {
      final base = _baseCtrl.text.trim().isEmpty
          ? kOllamaLocalBaseUrl
          : _baseCtrl.text.trim();
      final temp = AiProvider(
        id: 'ollama_probe',
        name: 'Ollama',
        kind: 'remote',
        baseUrl: base,
      );
      final r = await startOllama(temp);
      if (!mounted) return;
      setState(() => _info = r.message);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _save() async {
    final base = _baseCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (base.isEmpty || model.isEmpty) return;
    setState(() {
      _saving = true;
      _info = null;
    });
    try {
      await widget.onSave(base, model);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _info = friendlyErrorString(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String command) async {
    final ok = await copyToClipboard(command);
    if (!mounted) return;
    setState(() => _copied = ok ? command : null);
  }

  @override
  Widget build(BuildContext context) {
    final det = _detection;
    final ok = det?.ok ?? false;
    final existing = findOllamaProvider(widget.providers);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final canManual = _baseCtrl.text.trim().isNotEmpty &&
        _modelCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_fix_high, color: Color(0xFF9A8CFF)),
          SizedBox(width: 8),
          Expanded(child: Text('Configurer Ollama automatiquement')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_detecting)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Détection d\'Ollama sur cet appareil…'),
                    ),
                  ],
                )
              else if (ok) ..._successSection(det!)
              else ..._failureSection(det),
              if (_info != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  _info!,
                  style: const TextStyle(color: Color(0xFFFFB04A), fontSize: 12),
                ),
              ],
              if (existing != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Un fournisseur Ollama existant (« ${existing.name} ») sera '
                  'mis à jour (URL + modèle uniquement, nom conservé).',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_detecting) ...[
          TextButton.icon(
            onPressed: _detect,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Réessayer'),
          ),
          if (!ok && isAndroid)
            TextButton.icon(
              onPressed: _launching ? null : _launch,
              icon: const Icon(Icons.bolt, size: 16),
              label: Text(_launching ? 'Lancement…' : 'Démarrer Ollama'),
            ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        if (!_detecting)
          FilledButton(
            onPressed: ok
                ? (_saving ? null : _save)
                : (canManual ? (_saving ? null : _save) : null),
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
      ],
    );
  }

  List<Widget> _successSection(OllamaDetection det) {
    final chips = det.models
        .map(
          (m) => ActionChip(
            label: Text(m),
            selected: _modelCtrl.text.trim() == m,
            onPressed: () => setState(() => _modelCtrl.text = m),
          ),
        )
        .toList();
    return [
      SelectableText(
        ollamaDetectMessage(det),
        style: const TextStyle(color: Color(0xFF5BD27B), fontSize: 13),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _baseCtrl,
        decoration: const InputDecoration(
          labelText: 'URL de base',
          hintText: 'http://127.0.0.1:11434',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _modelCtrl,
        decoration: const InputDecoration(
          labelText: 'Modèle par défaut',
          hintText: 'qwen3:0.6b',
        ),
      ),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'Modèles détectés :',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    ];
  }

  List<Widget> _failureSection(OllamaDetection? det) {
    final steps = defaultTargetPlatform == TargetPlatform.android
        ? ollamaSetupSteps()
        : ollamaPcSteps();
    final canManual = _baseCtrl.text.trim().isNotEmpty &&
        _modelCtrl.text.trim().isNotEmpty;
    return [
      SelectableText(
        ollamaDetectMessage(
          det ?? const OllamaDetection(status: OllamaDetectStatus.unreachable),
        ),
        style: const TextStyle(color: Color(0xFFFFB04A), fontSize: 13),
      ),
      const SizedBox(height: 8),
      Text(
        platformOllamaHint(),
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      const SizedBox(height: 12),
      for (final step in steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${step.title} : ${step.command}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Copier la commande',
                icon: Icon(
                  _copied == step.command ? Icons.check : Icons.copy,
                  size: 16,
                ),
                onPressed: () => _copy(step.command),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Le serveur est déjà installé ailleurs ? Renseigne son adresse :',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _baseCtrl,
        decoration: const InputDecoration(
          labelText: 'URL de base',
          hintText: 'http://127.0.0.1:11434 ou http://IP-du-PC:11434',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _modelCtrl,
        decoration: const InputDecoration(
          labelText: 'Modèle par défaut',
          hintText: 'qwen3:0.6b',
        ),
      ),
      if (canManual)
        const Text(
          '(Enregistrer restera disponible pour un serveur manuel.)',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
    ];
  }
}