import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/catalog.dart';
import '../../core/chat_service.dart';
import '../../core/models.dart';
import '../../widgets/message_bubble.dart';

/// Résultat du choix d'un moteur (local ou cloud) + modèle.
typedef EngineChoice = ({String providerId, String modelId});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Conversation? _working;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _newConversation() async {
    final providers = ref.read(providersProvider).items;
    if (providers.isEmpty) {
      _snack('Ajoute d\'abord un fournisseur d\'IA (onglet « IA »).');
      return;
    }
    final ok = await showDialog<EngineChoice>(
      context: context,
      builder: (ctx) => _ConversationSetupDialog(providers: providers),
    );
    if (ok != null && mounted) {
      ref.read(chatsProvider).create(
            providerId: ok.providerId,
            modelId: ok.modelId,
          );
      _scrollToBottom();
    }
  }

  Future<void> _switchEngine(Conversation conv) async {
    final providers = ref.read(providersProvider).items;
    if (providers.isEmpty) {
      _snack('Ajoute d\'abord un fournisseur d\'IA (onglet « IA »).');
      return;
    }
    final ok = await showDialog<EngineChoice>(
      context: context,
      builder: (ctx) => _ConversationSetupDialog(
        providers: providers,
        currentProviderId: conv.providerId,
        currentModelId: conv.modelId,
      ),
    );
    if (ok != null && mounted) {
      conv.providerId = ok.providerId;
      conv.modelId = ok.modelId;
      await ChatService(ref.read(appStoreProvider)).setEngine(conv);
      ref.read(chatsProvider).push(conv);
      setState(() {});
      _snack('Moteur changé.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final chats = ref.read(chatsProvider);
    final conv = _working ?? chats.selected;
    if (text.isEmpty || conv == null || _busy) return;

    final service = ChatService(ref.read(appStoreProvider));
    _input.clear();
    setState(() => _busy = true);
    try {
      final updated = await service.send(
        conv: conv,
        text: text,
        onTick: () {
          if (mounted) setState(() {});
          _scrollToBottom();
        },
      );
      chats.push(updated);
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final conv = _working ?? chats.selected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.play_circle_outline, color: Color(0xFF6C4DF6)),
            const SizedBox(width: 8),
            Expanded(
              child: conv == null
                  ? const Text('PancartPlayer')
                  : Text(
                      conv.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
            ),
          ],
        ),
        actions: [
          if (conv != null)
            IconButton(
              tooltip: 'Changer local / cloud',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => _switchEngine(conv),
            ),
          if (conv != null)
            IconButton(
              tooltip: 'Supprimer la conversation',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await chats.delete(conv.id);
                _working = null;
              },
            ),
          IconButton(
            tooltip: 'Nouvelle conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          if (conv != null) _EngineBar(conv: conv, onSwitch: () => _switchEngine(conv)),
          Expanded(
            child: conv == null
                ? _EmptyChat(onCreate: _newConversation)
                : _MessagesList(
                    conv: conv,
                    scroll: _scroll,
                  ),
          ),
          _InputBar(
            controller: _input,
            busy: _busy,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

/// Bandeau « moteur actuel » : Local (sur appareil) ou Cloud (API).
class _EngineBar extends ConsumerWidget {
  const _EngineBar({required this.conv, required this.onSwitch});

  final Conversation conv;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(providersProvider).items;
    final models = ref.watch(modelsProvider);
    AiProvider? provider;
    for (final p in providers) {
      if (p.id == conv.providerId) provider = p;
    }

    final isLocal = conv.providerId == 'local' || provider?.kind == 'local';
    String label;
    if (isLocal) {
      final cat = catalogById(conv.modelId);
      label = 'Local · ${cat?.name ?? conv.modelId}';
      final dev = models.stateFor(conv.modelId);
      if (dev?.isDownloaded == true) label = '$label · sur appareil';
    } else if (provider == null) {
      label = 'Fournisseur introuvable — ${conv.modelId}';
    } else {
      label = 'Cloud · ${provider.name} · ${conv.modelId.isEmpty ? 'auto' : conv.modelId}';
    }

    final color = isLocal ? const Color(0xFF5BD27B) : const Color(0xFF6C4DF6);
    final icon = isLocal ? Icons.phone_android : Icons.cloud_outlined;

    return Material(
      color: const Color(0xFF181824),
      child: InkWell(
        onTap: onSwitch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 18),
                tooltip: 'Changer local / cloud',
                color: Colors.white38,
                visualDensity: VisualDensity.compact,
                onPressed: onSwitch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'N\'importe quel modèle. N\'importe quelle IA.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Crée une conversation : modèle léger en LOCAL, modèle lourd en CLOUD.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle conversation'),
          ),
        ],
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({required this.conv, required this.scroll});
  final Conversation conv;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (conv.messages.isEmpty) {
      return const Center(
        child: Text(
          'Écris ton premier message.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.all(12),
      itemCount: conv.messages.length + 1,
      itemBuilder: (context, i) {
        if (i >= conv.messages.length) return const SizedBox(height: 12);
        final m = conv.messages[i];
        return MessageBubble(
          role: m.role,
          content: m.content,
          isStreaming: m.isStreaming,
          error: m.error,
        );
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Ton message…',
                  filled: true,
                  fillColor: const Color(0xFF1D1D2B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix explicite : moteur LOCAL (sur appareil) ou CLOUD (API distante),
/// avec modèle guidé.
class _ConversationSetupDialog extends ConsumerStatefulWidget {
  const _ConversationSetupDialog({
    required this.providers,
    this.currentProviderId,
    this.currentModelId,
  });

  final List<AiProvider> providers;
  final String? currentProviderId;
  final String? currentModelId;

  @override
  ConsumerState<_ConversationSetupDialog> createState() =>
      _ConversationSetupDialogState();
}

class _ConversationSetupDialogState
    extends ConsumerState<_ConversationSetupDialog> {
  final TextEditingController _cloudModel = TextEditingController();

  String _kind = 'cloud';
  AiProvider? _cloudProvider;
  String? _localModelId;

  List<AiProvider> get _cloudProviders =>
      widget.providers.where((p) => p.kind != 'local').toList();

  @override
  void initState() {
    super.initState();
    final cloudProviders = _cloudProviders;
    _cloudProvider = cloudProviders.isNotEmpty
        ? cloudProviders.first
        : AiProvider(
            id: 'cloud_fallback',
            name: 'Cloud (API)',
            kind: 'remote',
            baseUrl: '',
            defaultModel: 'auto',
          );

    if (widget.currentProviderId != null) {
      final prov = widget.providers
          .where((p) => p.id == widget.currentProviderId)
          .toList();
      if (prov.isNotEmpty) {
        _kind = prov.first.kind == 'local' ? 'local' : 'cloud';
        if (_kind == 'cloud') _cloudProvider = prov.first;
      }
    }
    if (cloudProviders.isEmpty) _kind = 'local';

    final cur = widget.currentModelId;
    if (cur != null && cur.isNotEmpty && cur != 'auto') {
      if (_kind == 'local') {
        _localModelId = cur;
      } else {
        _cloudModel.text = cur;
      }
    } else if (_kind == 'local') {
      // premier modèle local déjà téléchargé et compatible
      final candidates = _localCandidates();
      for (final m in candidates) {
        if (m.isDownloaded()) {
          _localModelId = m.model.id;
          break;
        }
      }
    } else {
      _cloudModel.text = cloud.defaultModel.isNotEmpty ? cloud.defaultModel : 'auto';
    }
  }

  @override
  void dispose() {
    _cloudModel.dispose();
    super.dispose();
  }

  List<({CatalogModel model, DeviceModel? dev})> _localCandidates() {
    final models = ref.read(modelsProvider);
    return kCatalog
        .where((m) => m.sizeMb <= kLocalRamLimitMb)
        .map((m) => (model: m, dev: models.stateFor(m.id)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _kind == 'cloud'
        ? _cloudProvider != null && _cloudProviders.isNotEmpty
        : _localModelId != null;

    return AlertDialog(
      title: Text(widget.currentProviderId == null
          ? 'Nouvelle conversation'
          : 'Changer local / cloud'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'cloud',
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('Cloud'),
                  ),
                  ButtonSegment(
                    value: 'local',
                    icon: Icon(Icons.phone_android),
                    label: Text('Local'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              if (_kind == 'cloud') _buildCloud(context),
              if (_kind == 'local') _buildLocal(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: !canSend ? null : _save,
          child: Text(widget.currentProviderId == null ? 'Créer' : 'Valider'),
        ),
      ],
    );
  }

  Widget _buildCloud(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modèles lourds et cloud : aucune RAM nécessaire sur l\'appareil.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<AiProvider>(
          initialValue: _cloudProvider,
          decoration: const InputDecoration(labelText: 'Fournisseur cloud'),
          items: _cloudProviders
              .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
              .toList(),
          onChanged: (p) => setState(() {
            _cloudProvider = p;
            _cloudModel.text =
                p?.defaultModel.isNotEmpty == true ? p!.defaultModel : 'auto';
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cloudModel,
          decoration: const InputDecoration(
            labelText: 'Identifiant du modèle (API)',
            hintText: 'auto, gpt-4o-mini, llama-3.3-70b…',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['auto', 'gpt-4o-mini', 'llama-3.3-70b-versatile', 'qwen3-8b']
              .map((m) => ActionChip(
                    label: Text(m),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _cloudModel.text = m),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildLocal(BuildContext context) {
    final candidates = _localCandidates();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modèles compatibles avec la RAM du téléphone · exécutés sur place.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucun modèle compatible. Utilise le Cloud pour des modèles plus lourds.',
              style: TextStyle(color: Colors.white38),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView(
              shrinkWrap: true,
              children: candidates
                  .map((c) => _LocalModelTile(
                        candidate: c,
                        selected: c.model.id == _localModelId,
                        onTap: () => setState(() => _localModelId = c.model.id),
                      ))
                  .toList(),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Les modèles > ${(kLocalRamLimitMb / 1000).toStringAsFixed(0)} Go '
          '(type Ornith-9B) sont à exécuter en CLOUD.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  void _save() {
    if (_kind == 'cloud') {
      final p = _cloudProvider;
      if (p == null) return;
      Navigator.pop(
        context,
        (providerId: p.id, modelId: _cloudModel.text.trim()),
      );
    } else {
      final id = _localModelId;
      if (id == null) return;
      Navigator.pop(context, (providerId: 'local', modelId: id));
    }
  }
}

class _LocalModelTile extends StatelessWidget {
  const _LocalModelTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final ({CatalogModel model, DeviceModel? dev}) candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = candidate.model;
    final downloaded = candidate.dev?.isDownloaded == true;

    return Card(
      color: const Color(0xFF1D1D2B),
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          downloaded ? Icons.phone_android : Icons.download_outlined,
          color: selected ? const Color(0xFF6C4DF6) : Colors.white38,
        ),
        title: Text(
          m.name,
          overflow: TextOverflow.ellipsis,
          style: selected
              ? const TextStyle(color: Color(0xFF9A8CFF))
              : null,
        ),
        subtitle: Text(
          '${(m.sizeMb / 1000).toStringAsFixed(1)} Go · ${downloaded ? 'sur appareil' : 'à télécharger (onglet Modèles)'}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Radio<String>(
          value: m.id,
          groupValue: selected ? m.id : null,
          onChanged: downloaded ? (_) => onTap() : null,
        ),
        onTap: downloaded ? onTap : null,
      ),
    );
  }
}

extension on ({CatalogModel model, DeviceModel? dev}) {
  bool isDownloaded() => this.dev?.isDownloaded == true;
}