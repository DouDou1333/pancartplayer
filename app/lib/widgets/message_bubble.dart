import 'package:flutter/material.dart';

/// Bulle de message du chat (utilisateur / assistant), avec état de streaming
/// et affichage d'erreur éventuel.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.isStreaming = false,
    this.error = '',
  });

  final String role;
  final String content;
  final bool isStreaming;
  final String error;

  bool get _isUser => role == 'user';
  bool get _isSystem => role == 'system';

  @override
  Widget build(BuildContext context) {
    if (_isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            content,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final aligned = Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: _isUser
              ? const Color(0xFF4C3A9E)
              : const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(_isUser ? 16 : 4),
            bottomRight: Radius.circular(_isUser ? 4 : 16),
          ),
        ),
        child: error.isNotEmpty
            ? Text(
                error,
                style: const TextStyle(color: Color(0xFFFF7B7B)),
              )
            : Text(
                content.isEmpty && isStreaming ? '…' : content,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
      ),
    );

    return Column(
      crossAxisAlignment:
          _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        aligned,
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(right: 6, top: 2, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'génération…',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}