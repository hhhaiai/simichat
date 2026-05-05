import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/protocol_icons.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/connectivity_provider.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/prompt_provider.dart';
import '../../shared/providers/session_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/widgets/message_bubble.dart';
import '../../shared/widgets/streaming_bubble.dart';
import '../../shared/widgets/chat_input_bar.dart'
    show ChatInputBar, PendingAttachment;

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _hasTextNotifier = ValueNotifier<bool>(false);

  // 输入草稿缓存：按 sessionId 保存未发送文本
  static final Map<String, String> _draftCache = {};

  // 滚动监听：距底部超过一屏时显示 FAB
  bool _showScrollFab = false;
  bool _shouldAutoScroll = true;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onTextChanged);
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScrollChanged);
    _hasTextNotifier.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (_hasTextNotifier.value != hasText) {
      _hasTextNotifier.value = hasText;
    }
    // 缓存当前草稿
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null) {
      _draftCache[currentId] = _inputController.text;
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    final threshold = MediaQuery.of(context).size.height;
    final nearBottom = max <= 0 || (max - offset) < 200;
    final shouldShow = max > 0 && (max - offset) > threshold;
    if (shouldShow != _showScrollFab) {
      setState(() => _showScrollFab = shouldShow);
    }
    _shouldAutoScroll = nearBottom;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _shouldAutoScroll = true;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleSend(String content, List<PendingAttachment> attachments) {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) return;

    final streamState = ref.read(streamStateProvider(activeSessionId));
    if (streamState.isStreaming) {
      cancelStreaming(ref, activeSessionId);
      return;
    }

    if (content.isEmpty && attachments.isEmpty) return;
    _draftCache.remove(activeSessionId);
    sendMessage(
      ref: ref,
      sessionId: activeSessionId,
      content: content,
      attachments: attachments,
    );
    _focusNode.requestFocus();
  }

  /// 重试最后一条 user 消息（从 DB 读取，不依赖内存状态）
  void _handleRetry() {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) return;

    final messagesAsync = ref.read(messagesProvider(activeSessionId));
    messagesAsync.whenData((messages) {
      if (messages.isEmpty) return;
      // 找最后一条 user 消息
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i].role == 'user') {
          ref.read(streamStateProvider(activeSessionId).notifier).state =
              const StreamState();
          sendMessage(
            ref: ref,
            sessionId: activeSessionId,
            content: messages[i].content,
          );
          return;
        }
      }
    });
  }

  /// 从指定消息位置复制会话
  void _handleFork(String messageId) async {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) return;

    try {
      await forkSession(
        ref: ref,
        sourceSessionId: activeSessionId,
        upToMessageId: messageId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制会话'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('复制失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSessionId = ref.watch(activeSessionIdProvider);

    // 会话切换时恢复草稿（listener 在 build 外执行，不会干扰 IME）
    ref.listen(activeSessionIdProvider, (prev, next) {
      if (prev != next) {
        final draft = next != null ? _draftCache[next] : null;
        _inputController.text = draft ?? '';
        _hasTextNotifier.value = (_inputController.text.trim().isNotEmpty);
      }
    });

    if (activeSessionId == null) {
      return _buildEmptyState();
    }

    final messagesAsync = ref.watch(messagesProvider(activeSessionId));
    final streamState = ref.watch(streamStateProvider(activeSessionId));
    final isOnline = ref.watch(isOnlineProvider);

    return Stack(
      children: [
        Column(
          children: [
            // 顶部模型选择器
            _buildModelSelector(),

            // 消息列表（点击消息区域不收起键盘）
            Expanded(
              child: Listener(
                onPointerDown: (_) {
                  // 保持输入框焦点，避免键盘下缩
                  if (_focusNode.hasFocus) {
                    _focusNode.requestFocus();
                  }
                },
                child: messagesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                  data: (messages) {
                    if (messages.isEmpty && !streamState.isStreaming) {
                      return _buildEmptyChat();
                    }

                    if (_shouldAutoScroll) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollToBottom(),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.manual,
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      itemCount:
                          messages.length + (streamState.isStreaming ? 1 : 0),
                      itemBuilder: (_, index) {
                        if (index < messages.length) {
                          final msg = messages[index];
                          final isUser = msg.role == 'user';
                          return MessageBubble(
                            role: msg.role,
                            content: msg.content,
                            thinkingContent: msg.thinkingContent,
                            tokens: msg.tokens,
                            responseMs: msg.responseMs,
                            isUser: isUser,
                            onRetry: isUser ? null : _handleRetry,
                            onFork: () => _handleFork(msg.id),
                          );
                        }
                        // 流式输出中的气泡
                        return RepaintBoundary(
                          child: StreamingBubble(
                            content: streamState.currentContent,
                            thinking: streamState.currentThinking,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // 离线提示条
            if (!isOnline)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: Colors.orange.withValues(alpha: 0.1),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      '网络已断开',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),

            // 错误提示条
            if (streamState.error != null)
              _buildErrorBar(activeSessionId, streamState.error!),

            // 输入栏
            ChatInputBar(
              controller: _inputController,
              focusNode: _focusNode,
              isStreaming: streamState.isStreaming,
              hasTextNotifier: _hasTextNotifier,
              onSend: _handleSend,
            ),
          ],
        ),

        // 滚动到底部 FAB
        if (_showScrollFab)
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBar(String sessionId, String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _handleRetry, child: const Text('重试')),
          TextButton(
            onPressed: () {
              ref.read(streamStateProvider(sessionId).notifier).state =
                  const StreamState();
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector() {
    final modelsAsync = ref.watch(allModelsProvider);
    final selectedId = ref.watch(selectedModelIdProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);

    return modelsAsync.when(
      loading: () => const SizedBox(height: 8),
      error: (_, _) => const SizedBox(height: 8),
      data: (models) {
        if (models.isEmpty) return const SizedBox(height: 8);

        ChannelModelWithChannel? selected;
        if (selectedId != null) {
          try {
            selected = models.firstWhere(
              (m) => m.channelModel.id == selectedId,
            );
          } catch (_) {}
        }
        selected ??= models.first;

        final hasPrompt =
            ref.watch(systemPromptsProvider)[activeSessionId] != null;
        final scheme = Theme.of(context).colorScheme;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          color: scheme.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    onSelected: (modelId) async {
                      ref.read(selectedModelIdProvider.notifier).state =
                          modelId;
                      final activeId = ref.read(activeSessionIdProvider);
                      if (activeId != null) {
                        await ref
                            .read(sessionDaoProvider)
                            .updateDefaultModel(activeId, modelId);
                      }
                    },
                    offset: const Offset(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    constraints: const BoxConstraints(
                      maxWidth: 340,
                      maxHeight: 420,
                    ),
                    itemBuilder: (_) =>
                        _buildModelMenuItems(models, selected!.channelModel.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            getProtocolIcon(selected.channel.protocol),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Text(
                              selected.displayLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.tune,
                      size: 19,
                      color: hasPrompt
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    tooltip: '系统提示词',
                    onPressed: activeSessionId == null
                        ? null
                        : () => _showSystemPromptDialog(activeSessionId),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSystemPromptDialog(String sessionId) {
    final current = ref.read(systemPromptsProvider)[sessionId] ?? '';
    final controller = TextEditingController(text: current);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('系统提示词'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入系统提示词（留空则使用默认）...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showPromptPicker(ctx, controller),
            icon: const Icon(Icons.library_books, size: 16),
            label: const Text('从提示词库选择'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              controller.clear();
              ref.read(systemPromptsProvider.notifier).setPrompt(sessionId, '');
              Navigator.pop(ctx);
            },
            child: const Text('清除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(systemPromptsProvider.notifier)
                  .setPrompt(sessionId, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showPromptPicker(
    BuildContext context,
    TextEditingController controller,
  ) {
    final promptsAsync = ref.read(promptNotifierProvider);
    promptsAsync.whenData((prompts) {
      if (prompts.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提示词库为空，请先在设置中添加')));
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择提示词'),
          children: [
            for (final p in prompts)
              SimpleDialogOption(
                onPressed: () {
                  controller.text = p.content;
                  Navigator.pop(ctx);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      p.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }

  List<PopupMenuEntry<String>> _buildModelMenuItems(
    List<ChannelModelWithChannel> models,
    String? selectedId,
  ) {
    final items = <PopupMenuEntry<String>>[];
    String? lastChannel;

    for (final m in models) {
      if (m.channel.name != lastChannel) {
        if (lastChannel != null) items.add(const PopupMenuDivider());
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              m.channel.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
        );
        lastChannel = m.channel.name;
      }

      items.add(
        PopupMenuItem<String>(
          value: m.channelModel.id,
          child: Row(
            children: [
              if (m.channelModel.id == selectedId)
                Icon(Icons.check, size: 16, color: Colors.green[600])
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.channelModel.modelName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: m.channelModel.id == selectedId
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildEmptyState() {
    return const Center(child: Text('选择或新建一个会话'));
  }

  void _fillInputAndFocus(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    _hasTextNotifier.value = true;
    _focusNode.requestFocus();
  }

  Widget _buildEmptyChat() {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = ['解释一个复杂概念', '帮我写一封邮件', '生成跨平台发布清单', '分析一段代码'];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '今天想聊什么？',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final text in suggestions)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _fillInputAndFocus(text),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
