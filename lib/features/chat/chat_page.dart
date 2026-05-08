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
import '../../shared/widgets/compact_model_selector.dart';
import '../skills/skills_hub_page.dart';

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
  static const _maxDraftCacheSize = 50;

  // 滚动监听：距底部超过一屏时显示 FAB
  bool _showScrollFab = false;
  bool _shouldAutoScroll = true;

  // 会话内临时模型覆盖
  String? _pendingModelId;
  bool _isSubmitting = false;

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
      // 限制缓存大小，移除最旧的条目
      if (_draftCache.length > _maxDraftCacheSize) {
        final keysToRemove = _draftCache.keys.take(_draftCache.length - _maxDraftCacheSize).toList();
        for (final key in keysToRemove) {
          _draftCache.remove(key);
        }
      }
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

  Future<bool> _handleSend(
    String content,
    List<PendingAttachment> attachments,
  ) async {
    if (_isSubmitting) return false;

    var activeSessionId = ref.read(activeSessionIdProvider);

    if (activeSessionId != null) {
      final streamState = ref.read(streamStateProvider(activeSessionId));
      if (streamState.isStreaming) {
        cancelStreaming(ref, activeSessionId);
        return true;
      }
    }

    if (content.isEmpty && attachments.isEmpty) return false;

    if (mounted) {
      setState(() => _isSubmitting = true);
    } else {
      _isSubmitting = true;
    }

    try {
      activeSessionId ??= await createNewSession(ref);
      if (!mounted) return false;
      final sent = await sendMessage(
        ref: ref,
        sessionId: activeSessionId,
        content: content,
        overrideModelId: _pendingModelId,
        attachments: attachments,
      );
      if (!mounted) return false;
      if (!sent) {
        _draftCache[activeSessionId] = content;
        _inputController.text = content;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: content.length),
        );
        _hasTextNotifier.value = content.trim().isNotEmpty;
        return false;
      }
      _draftCache.remove(activeSessionId);
      _inputController.clear();
      _hasTextNotifier.value = false;
      setState(() => _pendingModelId = null);
      _focusNode.requestFocus();
      return true;
    } catch (e) {
      if (!mounted) return false;
      _inputController.text = content;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: content.length),
      );
      _hasTextNotifier.value = content.trim().isNotEmpty;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败: $e')));
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      } else {
        _isSubmitting = false;
      }
    }
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
        _pendingModelId = null;
        if (next != null) {
          ref.read(sessionDaoProvider).getSession(next).then((session) {
            if (!mounted || ref.read(activeSessionIdProvider) != next) return;
            ref.read(selectedModelIdProvider.notifier).state =
                session?.defaultChannelModelId;
          });
        }
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
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                          // 解析模型名
                          final modelsAsync = ref.watch(allModelsProvider);
                          final modelName = modelsAsync.whenOrNull(
                            data: (models) {
                              if (msg.channelModelId != null) {
                                  return models
                                      .where((m) => m.channelModel.id == msg.channelModelId)
                                      .firstOrNull
                                      ?.displayLabel;
                              }
                              return null;
                            },
                          );
                          return MessageBubble(
                            role: msg.role,
                            content: msg.content,
                            thinkingContent: msg.thinkingContent,
                            tokens: msg.tokens,
                            responseMs: msg.responseMs,
                            isUser: isUser,
                            modelName: modelName,
                            onRetry: isUser ? null : _handleRetry,
                            onFork: () => _handleFork(msg.id),
                          );
                        }
                        // 流式输出中的气泡
                        final modelsAsync = ref.watch(allModelsProvider);
                        final streamingModelName = modelsAsync.whenOrNull(
                          data: (models) {
                            final id =
                                _pendingModelId ??
                                ref.read(selectedModelIdProvider);
                            if (id != null) {
                                final match = models
                                    .where((m) => m.channelModel.id == id)
                                    .firstOrNull;
                                if (match != null) return match.displayLabel;
                            }
                            return models.isNotEmpty
                                ? models.first.displayLabel
                                : null;
                          },
                        );
                        return RepaintBoundary(
                          child: StreamingBubble(
                            content: streamState.currentContent,
                            thinking: streamState.currentThinking,
                            modelName: streamingModelName,
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
              modelSelector: CompactModelSelector(
                selectedModelId: _pendingModelId,
                onModelSelected: (modelId) {
                  setState(() => _pendingModelId = modelId);
                },
              ),
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

  Widget _buildLandingModelSelector() {
    final modelsAsync = ref.watch(allModelsProvider);
    final selectedId = _pendingModelId ?? ref.watch(selectedModelIdProvider);
    final scheme = Theme.of(context).colorScheme;

    return modelsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (models) {
        if (models.isEmpty) return const SizedBox.shrink();

        ChannelModelWithChannel selected = models.first;
        if (selectedId != null) {
          try {
            selected = models.firstWhere(
              (m) => m.channelModel.id == selectedId,
            );
          } catch (_) {}
        }

        return Column(
          children: [
            Text(
              '当前模型',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            CompactModelSelector(
              selectedModelId: selected.channelModel.id,
              onModelSelected: (modelId) {
                ref.read(selectedModelIdProvider.notifier).state = modelId;
                setState(() => _pendingModelId = modelId);
              },
            ),
          ],
        );
      },
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
                      Icons.extension_outlined,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                    tooltip: 'Skills 市场',
                    onPressed: () => showSkillsHubSheet(context),
                  ),
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SystemPromptPage(
          initialPrompt: current,
          onSave: (text) {
            ref.read(systemPromptsProvider.notifier).setPrompt(sessionId, text);
          },
        ),
      ),
    );
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
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'AI Chat',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '下面是当前模型，开始前可以先切换。',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLandingModelSelector(),
                    const SizedBox(height: 28),
                    _buildEmptyChat(),
                  ],
                ),
              ),
            ),
          ),
        ),
        ChatInputBar(
          controller: _inputController,
          focusNode: _focusNode,
          isStreaming: false,
          hasTextNotifier: _hasTextNotifier,
          onSend: _handleSend,
        ),
      ],
    );
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
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.8,
                              ),
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

/// 系统提示词页面：分类浏览 + 自定义编辑
class _SystemPromptPage extends StatefulWidget {
  const _SystemPromptPage({required this.initialPrompt, required this.onSave});

  final String initialPrompt;
  final ValueChanged<String> onSave;

  @override
  State<_SystemPromptPage> createState() => _SystemPromptPageState();
}

class _SystemPromptPageState extends State<_SystemPromptPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final TabController _tabController;
  bool _hasChanges = false;

  static const _categories = [
    _CategoryDef('全部', Icons.apps_outlined, 'all'),
    _CategoryDef('创作', Icons.brush_outlined, '创作'),
    _CategoryDef('办公', Icons.business_center_outlined, '办公'),
    _CategoryDef('医疗健康', Icons.health_and_safety_outlined, '医疗'),
    _CategoryDef('学习辅导', Icons.school_outlined, '学习'),
    _CategoryDef('使用工具', Icons.build_outlined, '工具'),
    _CategoryDef('教学辅助', Icons.menu_book_outlined, '教学'),
    _CategoryDef('法律服务', Icons.gavel_outlined, '法律'),
    _CategoryDef('生活', Icons.favorite_outline, '生活'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
    _controller.addListener(_onTextChanged);
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _usePrompt(String content) {
    _controller.text = content;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('系统提示词'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_controller.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _categories
              .map((c) => Tab(icon: Icon(c.icon, size: 18), text: c.label))
              .toList(),
        ),
      ),
      body: Column(
        children: [
          // 当前自定义提示词区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前提示词', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '设定 AI 的角色和行为准则，留空则使用模型默认。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 80,
                    maxHeight: 160,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      hintText: '点击输入自定义系统提示词...',
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${_controller.text.length} 字',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (_controller.text.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _controller.clear();
                          widget.onSave('');
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('清除', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 提示词库 Tab 浏览
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories.map((cat) {
                return _PromptListView(category: cat.key, onUse: _usePrompt);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDef {
  final String label;
  final IconData icon;
  final String key;
  const _CategoryDef(this.label, this.icon, this.key);
}

/// 提示词列表（按分类）
class _PromptListView extends ConsumerWidget {
  const _PromptListView({required this.category, required this.onUse});

  final String category;
  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptsAsync = ref.watch(promptNotifierProvider);

    return promptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (prompts) {
        final filtered = category == 'all'
            ? prompts
            : prompts
                  .where(
                    (p) => p.category == category || p.category == 'general',
                  )
                  .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '暂无提示词',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可在设置 → 提示词库中添加',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
          itemBuilder: (_, i) {
            final p = filtered[i];
            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  _categoryIcon(p.category),
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(p.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                p.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: () => onUse(p.content),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('使用'),
              ),
            );
          },
        );
      },
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case '创作':
        return Icons.brush_outlined;
      case '办公':
        return Icons.business_center_outlined;
      case '医疗':
        return Icons.health_and_safety_outlined;
      case '学习':
        return Icons.school_outlined;
      case '工具':
        return Icons.build_outlined;
      case '教学':
        return Icons.menu_book_outlined;
      case '法律':
        return Icons.gavel_outlined;
      case '生活':
        return Icons.favorite_outline;
      default:
        return Icons.text_snippet_outlined;
    }
  }
}
