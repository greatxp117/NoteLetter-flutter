import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/chat_notifier.dart';
import '../models/chat_message.dart';
import '../theme/app_colors.dart';

class ChatInterface extends StatefulWidget {
  const ChatInterface({super.key});

  @override
  State<ChatInterface> createState() => _ChatInterfaceState();
}

class _ChatInterfaceState extends State<ChatInterface> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatNotifier>(
      builder: (context, notifier, _) {
        _scrollToBottom();
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: notifier.messages.length + (notifier.isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (notifier.isTyping && index == notifier.messages.length) {
                    return const _TypingIndicator();
                  }
                  return _MessageBubble(message: notifier.messages[index]);
                },
              ),
            ),
            _InputBar(
              controller: _controller,
              onSend: (text) {
                if (text.trim().isEmpty) return;
                notifier.sendMessage(text);
                _controller.clear();
              },
            ),
          ],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 64),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: isDark ? AppColors.secondaryDark : AppColors.secondaryLight,
              child: Icon(Icons.person, size: 16, color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 64),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: primary.withValues(alpha: 0.15),
            child: Icon(Icons.auto_awesome, size: 16, color: primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : AppColors.cardLight,
                    border: Border.all(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(message.text, style: theme.textTheme.bodyMedium),
                ),
                if (message.citations.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: message.citations
                        .map((c) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.secondaryDark : AppColors.secondaryLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file,
                                      size: 10,
                                      color: isDark
                                          ? AppColors.mutedForegroundDark
                                          : AppColors.mutedForeground),
                                  const SizedBox(width: 4),
                                  Text(
                                    c,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isDark
                                          ? AppColors.mutedForegroundDark
                                          : AppColors.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];
  final List<Animation<double>> _animations = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
      final animation = Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      _controllers.add(controller);
      _animations.add(animation);
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) controller.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 64),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: primary.withValues(alpha: 0.15),
            child: Icon(Icons.auto_awesome, size: 16, color: primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : AppColors.cardLight,
              border:
                  Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => AnimatedBuilder(
                  animation: _animations[i],
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, _animations[i].value),
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 5,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Ask about your knowledge base...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) widget.onSend(text);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () {},
            color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: widget.controller.text.trim().isEmpty
                ? (isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground)
                : primary),
            onPressed: widget.controller.text.trim().isEmpty
                ? null
                : () => widget.onSend(widget.controller.text),
          ),
        ],
      ),
    );
  }
}
