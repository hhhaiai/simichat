import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'features/marketplace/marketplace_page.dart';
import 'features/search/search_sheet.dart';
import 'core/database/app_database.dart';
import 'core/skills/skill.dart' show builtInSkills;
import 'core/notification/notification_service.dart';
import 'core/database/dao/channel_dao.dart';
import 'shared/widgets/sidebar.dart';
import 'shared/providers/chat_provider.dart';
import 'shared/providers/channel_provider.dart';
import 'shared/providers/database_provider.dart';
import 'shared/providers/session_provider.dart';
import 'shared/providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }

  // 初始化数据库并植入内置 Skills
  final db = AppDatabase();
  try {
    await _seedBuiltInSkills(db);
  } catch (e) {
    debugPrint('Seed built-in skills failed: $e');
  }
  await db.close();

  runApp(const ProviderScope(child: AiChatApp()));
}

/// 首次启动时植入内置 Skills（幂等：已存在则跳过）
Future<void> _seedBuiltInSkills(AppDatabase db) async {
  for (final skill in builtInSkills) {
    final existing = await db.skillDao.getSkill(skill.id);
    if (existing == null) {
      await db.skillDao.insertSkill(
        id: skill.id,
        name: skill.name,
        description: skill.description,
        instructions: skill.instructions,
        isEnabled: false, // 默认不启用，用户手动开启
      );
    }
  }
}

class AiChatApp extends ConsumerWidget {
  const AiChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'AI Chat',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF10A37F),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF10A37F),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: themeMode,
      routes: {
        '/': (_) => const ResponsiveShell(),
        '/settings': (_) => const SettingsPage(),
        '/marketplace': (_) => const MarketplacePage(),
      },
    );
  }
}

/// 键盘快捷键定义
class _NewSessionIntent extends Intent {
  const _NewSessionIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _CancelStreamingIntent extends Intent {
  const _CancelStreamingIntent();
}

/// 响应式外壳：桌面端固定侧边栏，移动端 Drawer
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key});

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  static const _kDesktopBreakpoint = 720.0;

  @override
  void initState() {
    super.initState();
    // 首次启动时，如果没有会话则自动创建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSelectOrCreateSession();
    });
  }

  void _autoSelectOrCreateSession() {
    final sessionsAsync = ref.read(sessionsProvider);
    final activeId = ref.read(activeSessionIdProvider);
    if (activeId != null) return;

    sessionsAsync.whenData((sessions) {
      if (sessions.isEmpty) {
        createNewSession(ref);
      } else {
        ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // watch 以保持响应式（子组件依赖这些 provider）
    ref.watch(sessionsProvider);
    ref.watch(activeSessionIdProvider);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyK): const _SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyK): const _SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape):
            const _CancelStreamingIntent(),
      },
      child: Actions(
        actions: {
          _NewSessionIntent: CallbackAction<_NewSessionIntent>(
            onInvoke: (_) {
              createNewSession(ref);
              return null;
            },
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              showSearchSheet(context);
              return null;
            },
          ),
          _CancelStreamingIntent: CallbackAction<_CancelStreamingIntent>(
            onInvoke: (_) {
              final activeId = ref.read(activeSessionIdProvider);
              if (activeId != null) {
                cancelStreaming(ref, activeId);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > _kDesktopBreakpoint;
              if (isDesktop) {
                return _buildDesktopLayout(context, ref);
              } else {
                return _buildMobileLayout(context, ref);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏（固定 280px）
          const SizedBox(
            width: 280,
            child: Sidebar(),
          ),
          // 分隔线
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          // 对话区
          Expanded(
            child: Scaffold(
              appBar: _buildChatAppBar(context, ref),
              body: const ChatPage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _buildChatAppBar(context, ref, showMenuButton: true),
      drawer: const Drawer(
        child: SafeArea(child: Sidebar()),
      ),
      body: const ChatPage(),
    );
  }

  /// 移动端 AppBar 标题：会话名 + 当前模型（hamburger 旁边可见）
  Widget _buildMobileTitle(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Session?> activeSession,
  ) {
    final modelsAsync = ref.watch(allModelsProvider);
    final selectedId = ref.watch(selectedModelIdProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final sessionDefaultModelId = activeSession.whenOrNull(
      data: (session) => session?.defaultChannelModelId,
    );
    final currentModelId = selectedId ?? sessionDefaultModelId;

    final modelLabel = modelsAsync.whenOrNull(
      data: (models) {
        if (currentModelId != null) {
          final match = models
              .where((m) => m.channelModel.id == currentModelId)
              .firstOrNull;
          if (match != null) return match.displayLabel;
        }
        return null;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('AI Chat', style: TextStyle(fontSize: 16)),
        modelsAsync.when(
          loading: () => Text(
            '加载模型中…',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          error: (_, _) => Text(
            '未选择模型',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          data: (models) {
            if (models.isEmpty) {
              return Text(
                '未选择模型',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              );
            }

            return PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              tooltip: '切换模型',
              onSelected: (modelId) async {
                ref.read(selectedModelIdProvider.notifier).state = modelId;
                if (activeSessionId != null) {
                  await ref
                      .read(sessionDaoProvider)
                      .updateDefaultModel(activeSessionId, modelId);
                }
              },
              itemBuilder: (_) => _buildMobileModelMenuItems(
                context,
                models,
                currentModelId,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      modelLabel ?? '未选择模型',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more, size: 14, color: Colors.grey[500]),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMobileModelMenuItems(
    BuildContext context,
    List<ChannelModelWithChannel> models,
    String? selectedId,
  ) {
    final items = <PopupMenuEntry<String>>[];
    final grouped = <String, List<ChannelModelWithChannel>>{};

    for (final model in models) {
      grouped.putIfAbsent(model.channel.name, () => []).add(model);
    }

    for (final entry in grouped.entries) {
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ),
      );

      for (final model in entry.value) {
        final isSelected = model.channelModel.id == selectedId;
        items.add(
          PopupMenuItem<String>(
            value: model.channelModel.id,
            child: Row(
              children: [
                if (isSelected)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    model.channelModel.modelName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
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
    }

    return items;
  }

  PreferredSizeWidget _buildChatAppBar(
    BuildContext context,
    WidgetRef ref, {
    bool showMenuButton = false,
  }) {
    final activeSession = ref.watch(activeSessionProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);

    return AppBar(
      leading: showMenuButton
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: showMenuButton
          ? _buildMobileTitle(context, ref, activeSession)
          : activeSession.when(
              loading: () => const Text('AI Chat'),
              error: (_, _) => const Text('AI Chat'),
              data: (session) => Text(
                session?.title ?? 'AI Chat',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '新建会话',
          onPressed: () => createNewSession(ref),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '重试回复',
          onPressed: activeSessionId == null
              ? null
              : () => retryLastUserMessage(ref, sessionId: activeSessionId),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '设置',
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }
}
