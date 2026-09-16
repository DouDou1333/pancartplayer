import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/chat_service.dart';
import '../../core/models.dart';
import '../../widgets/message_bubble.dart';

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
    final providers = ref.read(providersProvider);
    if (providers.items.isEmpty) {
      _snack('Ajoute d\'abord un fournisseur d\'IA (onglet « IA »).');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _NewConversationDialog(providerOptions: providers.items),
    );
    if (ok == true && mounted) {
      ref.read(chatsProvider).reload();
      _scrollToBottom();
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
            'Crée une conversation pour commencer.',
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

class _NewConversationDialog extends ConsumerStatefulWidget {
  const _NewConversationDialog({required this.providerOptions});

  final List<AiProvider> providerOptions;

  @override
  ConsumerState<_NewConversationDialog> createState() =>
      _NewConversationDialogState();
}

class _NewConversationDialogState extends ConsumerState<_NewConversationDialog> {
  AiProvider? _provider;
  final TextEditingController _model = TextEditingController();

  String get _modelHint =>
      _provider?.kind == 'local'
          ? 'Identifiant du catalogue local (ex: qwen3-4b)'
          : 'Identifiant du modèle (API)';

  @override
  void initState() {
    super.initState();
    if (widget.providerOptions.isNotEmpty) {
      _provider = widget.providerOptions.first;
      _model.text = _provider!.kind == 'local'
          ? 'qwen3-4b'
          : _provider!.defaultModel.isNotEmpty
              ? _provider!.defaultModel
              : 'auto';
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle conversation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<AiProvider>(
            initialValue: _provider,
            decoration: const InputDecoration(labelText: 'Fournisseur'),
            items: widget.providerOptions
                .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                .toList(),
            onChanged: (p) {
              setState(() {
                _provider = p;
                _model.text = p?.kind == 'local'
                    ? 'qwen3-4b'
                    : p?.defaultModel.isNotEmpty == true
                        ? p!.defaultModel
                        : 'auto';
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: _modelHint,
              hintText: 'auto, gpt-4o-mini, llama3, qwen3-4b…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final p = _provider;
            if (p == null) {
              Navigator.pop(context, false);
              return;
            }
            Navigator.pop(context, true);
            ref.read(chatsProvider).create(
                  providerId: p.id,
                  modelId: _model.text.trim().isEmpty
                      ? 'auto'
                      : _model.text.trim(),
                );
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}