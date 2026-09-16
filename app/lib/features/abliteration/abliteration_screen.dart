import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ablit_service.dart';
import '../../core/app_providers.dart';

class AbliterationScreen extends ConsumerStatefulWidget {
  const AbliterationScreen({super.key});

  @override
  ConsumerState<AbliterationScreen> createState() => _AbliterationScreenState();
}

class _AbliterationScreenState extends ConsumerState<AbliterationScreen> {
  final TextEditingController _ggufPath = TextEditingController(
      text: '/storage/emulated/0/Download/ornith-9b-uncensored-Q4_K_M.gguf');
  String _output = '';
  bool _showScript = false;

  @override
  void dispose() {
    _ggufPath.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final nb = ref.read(ablitControllerProvider);
    await nb.add(_ggufPath.text.trim().split('/').last);
    if (!mounted) return;
    setState(() {
      _output = AblitService.buildLocalScript(_ggufPath.text.trim());
      _showScript = true;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _output));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Script copié — à lancer sur une machine ≥ 32 Go RAM ou dans Colab.')),
      );
    }
  }

  Future<void> _showColab() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ablitération dans Colab (gratuit)'),
        content: SingleChildScrollView(
          child: SelectableText(AblitService.buildColabMarkdown()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(ablitControllerProvider);
    final canRun = AblitService.instance.canRunLocally;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ablitération'),
        actions: [
          IconButton(
            tooltip: 'Mode Colab gratuit',
            icon: const Icon(Icons.school_outlined),
            onPressed: _showColab,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: const Color(0xFF1D1D2B),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Qu\'est-ce que l\'ablitération ?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Elle supprime la « direction du refus » d\'un modèle : il '
                    'répond au lieu de se censurer. Le calcul exige une machine '
                    'à grande RAM ou un GPU — d\'où le pipeline génératif ci-dessous.',
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canRun ? 'Exécution locale possible (desktop).' : 'Exécution locale indisponible ici (mobile/faible RAM) → utilise Colab.',
                    style: TextStyle(
                      color: canRun ? const Color(0xFF5BD27B) : const Color(0xFFF2C94C),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'GGUF source (chemin sur la machine de travail)',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ggufPath,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1D1D2B),
              hintText: '/chemin/vers/mon-model.gguf',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Générer le pipeline',
                onPressed: _generate,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.tune),
                label: const Text('Générer le pipeline'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showColab,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Notebook Colab + commandes'),
              ),
            ],
          ),
          if (_showScript) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF15151F),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Pipeline généré — exécution : machine ≥ 32 Go RAM',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: _copy,
                        ),
                      ],
                    ),
                    SelectableText(
                      _output,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF9AFF9A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Historique des jobs', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('${jobs.jobs.length}', style: const TextStyle(color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 4),
          if (jobs.jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun job pour l\'instant.',
                  style: TextStyle(color: Colors.white38)),
            )
          else
            ...jobs.jobs.map((j) => Card(
                  color: const Color(0xFF1D1D2B),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.science_outlined, color: Color(0xFF9A8CFF)),
                    title: Text(j.sourceModelName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${j.state.name} · ${j.step}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Text('→ pipeline', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                )),
          const SizedBox(height: 16),
          const Text(
            'Astuce : une fois ton GGUF ablité généré (ex: ornith-abliterated-Q4_K_M.gguf), '
            'place-le dans un dossier connu et fais-le correspondre à un modèle du catalogue '
            '— l\'import des modèles custom arrive en v1.1.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              final nb = ref.read(ablitControllerProvider);
              nb.add(DateTime.now().toIso8601String());
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter manuellement un job'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}