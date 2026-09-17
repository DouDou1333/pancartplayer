import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          _SectionTitle('Général'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('À propos'),
            subtitle: const Text('PancartPlayer v0.1.0 — plateforme libre'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('PancartPlayer'),
                content: const Text(
                  'Plateforme libre pour faire tourner n\'importe quel modèle GGUF '
                  'et se connecter à n\'importe quelle IA (OpenAI, OpenRouter, Groq, '
                  'Ollama, etc.) — le tout dans une seule application.\n\n'
                  'Licence : MIT\n'
                  'Ablitération intégrée pour les modèles censurés.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),

          _SectionTitle('Chemin des modèles'),
          FutureBuilder<String>(
            future: modelsDir(),
            builder: (context, snap) {
              if (snap.hasError) return const SizedBox();
              final path = snap.data ?? '';
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(path.isNotEmpty ? p.basename(path) : '…'),
                subtitle: Text(path, style: const TextStyle(fontSize: 12)),
              );
            },
          ),

          _SectionTitle('Prompt système'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Prompt système par défaut'),
            subtitle: Text(
              store.getString('system_prompt', 'Tu es un assistant utile et précis.'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              final ctrl = TextEditingController(
                  text: store.getString('system_prompt', 'Tu es un assistant utile et précis.'));
              final result = await showDialog<String>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Modifier le prompt système'),
                  content: TextField(
                    controller: ctrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Tu es un assistant utile et précis.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                      child: const Text('Valider'),
                    ),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                await store.setString('system_prompt', result);
              }
            },
          ),

          _SectionTitle('Température par défaut'),
          const _TemperatureSlider(),

          const _SectionTitle('À venir'),
          ListTile(
            leading: const Icon(Icons.construction),
            title: const Text('Thème clair'),
            subtitle: const Text('Version 1.1'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Curseur de température persistant (rebuild local propre, sans hack).
class _TemperatureSlider extends ConsumerStatefulWidget {
  const _TemperatureSlider();

  @override
  ConsumerState<_TemperatureSlider> createState() => _TemperatureSliderState();
}

class _TemperatureSliderState extends ConsumerState<_TemperatureSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = ref.read(appStoreProvider).getDouble('temperature', 0.7);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Slider(
        value: _value,
        min: 0,
        max: 2.0,
        divisions: 20,
        label: _value.toStringAsFixed(1),
        onChanged: (v) async {
          setState(() => _value = v);
          await ref.read(appStoreProvider).setDouble('temperature', v);
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF9A8CFF),
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}