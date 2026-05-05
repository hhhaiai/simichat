import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'core/database/app_database.dart';
import 'core/notification/notification_service.dart';
import 'shared/widgets/sidebar.dart';
import 'shared/providers/chat_provider.dart';
import 'shared/providers/channel_provider.dart';
import 'shared/providers/session_provider.dart';
import 'shared/providers/settings_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService().init();
  runApp(const ProviderScope(child: AiChatApp()));
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
  bool _autoCreated = false;

  @override
  Widget build(BuildContext context) {
    // 首次启动时，如果没有会话则自动创建
    final sessionsAsync = ref.watch(sessionsProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    if (!_autoCreated) {
      sessionsAsync.whenData((sessions) {
        if (sessions.isEmpty && activeId == null) {
          _autoCreated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            createNewSession(ref);
          });
        } else if (sessions.isNotEmpty && activeId == null) {
          // 有会话但没选中，选中第一个
          _autoCreated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
          });
        }
      });
    }

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
              // TODO: 打开搜索对话框
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

    final sessionTitle = activeSession.when(
      loading: () => 'AI Chat',
      error: (_, _) => 'AI Chat',
      data: (s) => s?.title ?? 'AI Chat',
    );

    final modelLabel = modelsAsync.whenOrNull(
      data: (models) {
        if (selectedId != null) {
          try {
            return models.firstWhere((m) => m.channelModel.id == selectedId).displayLabel;
          } catch (_) {}
        }
        return models.isNotEmpty ? models.first.displayLabel : null;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          sessionTitle,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        if (modelLabel != null)
          Text(
            modelLabel,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  PreferredSizeWidget _buildChatAppBar(
    BuildContext context,
    WidgetRef ref, {
    bool showMenuButton = false,
  }) {
    final activeSession = ref.watch(activeSessionProvider);

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
          icon: const Icon(Icons.settings),
          tooltip: '设置',
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }
}
