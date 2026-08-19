import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/generated/app_localizations.dart';

import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';
import 'features/marketplace/marketplace_page.dart';
import 'features/extensions/mobile_extensions_page.dart';
import 'features/search/search_sheet.dart';
import 'core/background/dreaming_background_workmanager.dart';
import 'core/deep_link/deep_link_service.dart';
import 'core/database/app_database.dart';
import 'core/skills/skill.dart' show builtInSkills;
import 'core/notification/notification_service.dart';
import 'core/smoke/release_background_smoke_harness.dart';
import 'core/smoke/release_deep_link_smoke_harness.dart';
import 'core/smoke/release_network_smoke_harness.dart';
import 'core/smoke/release_send_smoke_harness.dart';
import 'core/smoke/dreaming_reflection_smoke_harness.dart';
import 'core/smoke/android_background_dreaming_smoke_harness.dart';
import 'core/smoke/ios_background_dreaming_smoke_harness.dart';
import 'core/database/dao/channel_dao.dart';
import 'shared/providers/image_generation_provider.dart';
import 'shared/providers/audio_transcription_provider.dart';
import 'shared/providers/text_to_speech_provider.dart';
import 'shared/providers/universal_media_provider.dart';
import 'core/ai/universal_media_service.dart';
import 'core/ai/model_capability.dart';
import 'shared/widgets/sidebar.dart';
import 'shared/providers/chat_provider.dart';
import 'shared/providers/channel_provider.dart';
import 'shared/providers/connectivity_provider.dart';
import 'shared/providers/database_provider.dart';
import 'shared/providers/dreaming_provider.dart';
import 'shared/providers/session_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/reflection_provider.dart';
import 'shared/providers/user_profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (iosBackgroundDreamingSmokeEnabled) {
    await runIosBackgroundDreamingSmokeApp();
    return;
  }
  if (androidBackgroundDreamingSmokeEnabled) {
    await runAndroidBackgroundDreamingSmokeApp();
    return;
  }
  if (dreamingReflectionSmokeEnabled) {
    dreamingDigestCompleteNotifier =
        ({
          required String dayKey,
          required int originalMessageCount,
          int? totalOriginalMessageCount,
          required int memoryCandidateCount,
          int profileProposalCount = 0,
        }) async {};
    dreamingDigestFailedNotifier = ({required String dayKey}) async {};
    await runDreamingReflectionSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseSendSmokeEnabled) {
    await runReleaseSendSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseBackgroundSmokeEnabled) {
    await runReleaseBackgroundSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseNetworkSmokeEnabled) {
    await runReleaseNetworkSmokeApp(child: const AiChatApp());
    return;
  }
  if (releaseDeepLinkSmokeEnabled) {
    await runReleaseDeepLinkSmokeApp(
      buildApp: (observers) => AiChatApp(navigatorObservers: observers),
    );
    return;
  }

  // 首帧必须优先于所有可选初始化。iOS 上通知、后台任务或 SQLite 的系统
  // 调用可能慢于 Flutter 引擎启动；此前在 runApp 前等待它们会让用户只看到
  // 启动页/白屏。AppBootstrap 在第一帧后用同一个 Provider 数据库实例完成
  // 这些工作，任何单项失败都不会阻塞聊天主界面。
  runApp(const ProviderScope(child: AppBootstrap()));
}

typedef AppStartupTask = Future<void> Function();
typedef SkillSeedTask = Future<void> Function(AppDatabase database);
typedef AppStartupErrorReporter =
    void Function(String taskName, Object error, StackTrace stackTrace);

/// 常规启动完成后的非关键任务。
///
/// 保持任务顺序与旧启动链一致，但绝不让单项失败阻断后续任务。调用方必须在
/// 首帧后调用，确保慢速原生初始化不会阻塞可交互 UI。
@visibleForTesting
Future<void> runDeferredAppStartupTasks(
  AppDatabase database, {
  AppStartupTask? syncDreamingSchedule,
  AppStartupTask? initializeNotifications,
  SkillSeedTask? seedBuiltInSkills,
  AppStartupErrorReporter? onError,
}) async {
  void report(String taskName, Object error, StackTrace stackTrace) {
    if (onError != null) {
      onError(taskName, error, stackTrace);
      return;
    }
    debugPrint('$taskName failed: $error');
  }

  Future<void> runStep(String taskName, AppStartupTask task) async {
    try {
      await task();
    } catch (error, stackTrace) {
      report(taskName, error, stackTrace);
    }
  }

  await runStep(
    'Background Dreaming schedule',
    syncDreamingSchedule ?? syncDreamingBackgroundScheduleFromStorage,
  );
  await runStep(
    'Notification init',
    initializeNotifications ?? () => NotificationService().init(),
  );
  await runStep(
    'Seed built-in skills',
    () => (seedBuiltInSkills ?? _seedBuiltInSkills)(database),
  );
}

/// 将慢速启动任务移到首帧之后，保证即使原生插件或历史数据库异常，应用仍可
/// 立即呈现并保持可恢复的聊天入口。
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({
    super.key,
    this.startupTasksRunner,
    this.mediaRecoveryRunner,
  });

  @visibleForTesting
  final Future<void> Function(AppDatabase database)? startupTasksRunner;

  /// 测试可替换的媒体恢复入口；生产实现使用 ProviderScope 内同一个
  /// database/notifier，并在首帧后异步启动，不阻塞聊天页面。
  @visibleForTesting
  final Future<void> Function()? mediaRecoveryRunner;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final runStartupTasks =
          widget.startupTasksRunner ?? runDeferredAppStartupTasks;
      // databaseProvider 的生命周期归 ProviderScope 管理。不要创建并关闭第二个
      // AppDatabase，否则首次会话创建可能与 Skills 植入竞争同一个 SQLite 文件。
      unawaited(runStartupTasks(ref.read(databaseProvider)));
      unawaited(_runMediaRecovery());
    });
  }

  Future<void> _runMediaRecovery() async {
    try {
      await (widget.mediaRecoveryRunner ??
          () => startUniversalMediaRecovery(ref))();
    } catch (error) {
      debugPrint('Universal media recovery failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => const AiChatApp();
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

typedef DreamingDigestCompleteNotifier =
    Future<void> Function({
      required String dayKey,
      required int originalMessageCount,
      int? totalOriginalMessageCount,
      required int memoryCandidateCount,
      int profileProposalCount,
    });

typedef DreamingDigestFailedNotifier =
    Future<void> Function({required String dayKey});

Future<void> _defaultDreamingDigestCompleteNotifier({
  required String dayKey,
  required int originalMessageCount,
  int? totalOriginalMessageCount,
  required int memoryCandidateCount,
  int profileProposalCount = 0,
}) {
  return NotificationService().showDreamingDigestComplete(
    dayKey: dayKey,
    originalMessageCount: originalMessageCount,
    totalOriginalMessageCount: totalOriginalMessageCount,
    memoryCandidateCount: memoryCandidateCount,
    profileProposalCount: profileProposalCount,
  );
}

Future<void> _defaultDreamingDigestFailedNotifier({required String dayKey}) {
  return NotificationService().showDreamingDigestFailed(dayKey: dayKey);
}

@visibleForTesting
DreamingDigestCompleteNotifier dreamingDigestCompleteNotifier =
    _defaultDreamingDigestCompleteNotifier;

@visibleForTesting
DreamingDigestFailedNotifier dreamingDigestFailedNotifier =
    _defaultDreamingDigestFailedNotifier;

@visibleForTesting
void resetDreamingDigestCompleteNotifierForTesting() {
  dreamingDigestCompleteNotifier = _defaultDreamingDigestCompleteNotifier;
  dreamingDigestFailedNotifier = _defaultDreamingDigestFailedNotifier;
}

class AiChatApp extends ConsumerWidget {
  const AiChatApp({super.key, this.navigatorObservers = const []});

  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return MaterialApp(
      title: 'SimiAIChat',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      theme: _buildAppTheme(Brightness.light),
      darkTheme: _buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(normalizeFontScale(fontScale)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      navigatorObservers: navigatorObservers,
      routes: {
        '/': (_) => const ResponsiveShell(),
        '/settings': (_) => const SettingsPage(),
        '/marketplace': (_) => const MarketplacePage(),
        '/mobile-extensions': (_) => const MobileExtensionsPage(),
      },
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  return ThemeData(
    colorSchemeSeed: const Color(0xFF10A37F),
    brightness: brightness,
    useMaterial3: true,
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: EdgeInsets.fromLTRB(16, 8, 16, 120),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
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

/// 顶部模型选择器：移动端和桌面端共用同一套可访问的模型切换入口。
///
/// 这里的列表只来自本地已配置渠道，不把测试模型或模型名称当成云端能力。
/// 持久化和会话记录仍由 [switchConversationModel] 负责；本组件只负责把
/// 选择状态、加载状态和失败反馈稳定地呈现在聊天顶部。
class ChatModelSelector extends ConsumerWidget {
  const ChatModelSelector({super.key});

  static const selectorKey = ValueKey<String>('chat-model-selector');
  static const _maxControlWidth = 268.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(allModelsProvider);
    final allConfiguredAsync = ref.watch(allConfiguredModelsProvider);
    final selectedId = ref.watch(selectedModelIdProvider);
    final activeSession = ref.watch(activeSessionProvider);
    final preferredModelId = _preferredModelId(activeSession, selectedId);

    return modelsAsync.when(
      loading: () => _buildStateControl(
        context,
        icon: Icons.hourglass_top_rounded,
        label: '加载模型…',
        semanticsLabel: '模型选择器，正在加载模型列表',
        enabled: false,
      ),
      error: (_, _) => _buildStateControl(
        context,
        icon: Icons.error_outline_rounded,
        label: '模型加载失败 · 重试',
        semanticsLabel: '模型选择器，模型列表加载失败，点击重试',
        onPressed: () {
          ref.invalidate(allModelsProvider);
          _showMessage(context, '正在重新加载模型列表…');
        },
      ),
      data: (models) {
        if (models.isEmpty) {
          return _buildStateControl(
            context,
            icon: Icons.add_circle_outline_rounded,
            label: '未选择模型',
            semanticsLabel: '模型选择器，当前未选择模型，点击前往设置添加模型渠道',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          );
        }

        final current = _findModel(models, preferredModelId);
        final currentLabel = current?.displayLabel ?? '未选择模型';
        return Semantics(
          button: true,
          container: true,
          label: '模型选择器，当前模型：$currentLabel',
          hint: '点击打开模型列表',
          child: PopupMenuButton<String>(
            key: selectorKey,
            tooltip: '切换模型',
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(
              minWidth: 220,
              maxWidth: 340,
              maxHeight: 480,
            ),
            onSelected: (modelId) {
              final target = _findModel(
                allConfiguredAsync.valueOrNull ?? models,
                modelId,
              );
              if (target == null) return;
              if (!models.any((m) => m.channelModel.id == modelId)) {
                // 媒体模型：点击不是切换聊天模型，而是把该模型配置到
                // 对应的生成 / 语音工具上。
                unawaited(_applyMediaModel(context, ref, target));
                return;
              }
              unawaited(
                _switchModel(context, ref, target: target, previous: current),
              );
            },
            itemBuilder: (_) => _buildMenuItems(
              context,
              // 菜单展示全部已配置模型（含 TTS / STT / 生图等媒体模型，
              // 以能力标签标注且不可选）；聊天选择仍只允许聊天类模型。
              allConfiguredAsync.valueOrNull ?? models,
              selectedId: current?.channelModel.id,
              selectableIds: models
                  .map((m) => m.channelModel.id)
                  .toSet(),
            ),
            child: _buildModelControl(context, currentLabel),
          ),
        );
      },
    );
  }

  String? _preferredModelId(
    AsyncValue<Session?> activeSession,
    String? selectedId,
  ) {
    final sessionModelId = activeSession.whenOrNull(
      data: (session) => session?.defaultChannelModelId,
    );
    // 活动会话的默认模型是权威值；没有活动会话时才使用全局选择。
    return sessionModelId ?? selectedId;
  }

  ChannelModelWithChannel? _findModel(
    List<ChannelModelWithChannel> models,
    String? modelId,
  ) {
    if (modelId == null) return null;
    return models
        .where((model) => model.channelModel.id == modelId)
        .firstOrNull;
  }

  Widget _buildStateControl(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String semanticsLabel,
    VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return Semantics(
      button: true,
      container: true,
      enabled: enabled && onPressed != null,
      label: semanticsLabel,
      hint: onPressed == null ? null : '点击执行操作',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxControlWidth),
        child: SizedBox(
          // 完整状态控件保持 Material 最小触达高度；AppBar 同步增高，不把
          // 小尺寸视觉胶囊当成唯一的点击区域。
          height: 44,
          child: OutlinedButton.icon(
            key: selectorKey,
            onPressed: onPressed,
            icon: Icon(icon, size: 15),
            // OutlinedButton.icon 内部已经为 label 提供 Flexible；再次嵌套会
            // 触发冲突的 ParentData。
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelControl(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxControlWidth),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    List<ChannelModelWithChannel> models, {
    required String? selectedId,
    required Set<String> selectableIds,
  }) {
    // 旧版"按能力+名称"去重曾给同一模型写入重复行（chat 与媒体能力各一），
    // 菜单按 (渠道, 模型名) 去重：优先保留媒体能力行，避免同名重复与
    // 媒体模型被误显示为可选 Chat 行。
    final deduped = <String, ChannelModelWithChannel>{};
    for (final model in models) {
      final key = '${model.channel.id}:${model.channelModel.modelName}';
      final existing = deduped[key];
      if (existing == null ||
          (existing.channelModel.capability == 'chat' &&
              model.channelModel.capability != 'chat')) {
        deduped[key] = model;
      }
    }

    final grouped = <String, List<ChannelModelWithChannel>>{};
    for (final model in deduped.values) {
      grouped.putIfAbsent(model.channel.name, () => []).add(model);
    }

    final items = <PopupMenuEntry<String>>[];
    for (final entry in grouped.entries) {
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider(height: 1));
      }
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Semantics(
            header: true,
            child: Text(
              entry.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );

      for (final model in entry.value) {
        final isSelected = model.channelModel.id == selectedId;
        final isChatSelectable = selectableIds.contains(model.channelModel.id);
        final modelLabel = model.channelModel.modelName;
        final capabilityLabel = ModelCapability.label(
          model.channelModel.capability,
        );
        items.add(
          PopupMenuItem<String>(
            // 媒体模型（TTS / STT / 生图 / 视频 / 音乐 / 向量 / 重排）
            // 可点击：点击不是切换聊天模型，而是把该模型配置到对应工具。
            enabled: true,
            value: model.channelModel.id,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Semantics(
              container: true,
              selected: isSelected,
              label: isSelected
                  ? '${entry.key} / $modelLabel，当前已选择'
                  : isChatSelectable
                  ? '${entry.key} / $modelLabel'
                  : '${entry.key} / $modelLabel，$capabilityLabel，点击配置到对应工具',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : !isChatSelectable
                            ? Icon(
                                Icons.tune,
                                size: 15,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: isChatSelectable
                                ? null
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (!isChatSelectable) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            capabilityLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return items;
  }

  /// 媒体模型点击：把模型配置到对应工具（生图 / TTS / STT / 视频 / 音乐），
  /// 不修改会话默认聊天模型。
  Future<void> _applyMediaModel(
    BuildContext context,
    WidgetRef ref,
    ChannelModelWithChannel model,
  ) async {
    final name = model.channelModel.modelName;
    final capability = model.channelModel.capability;
    final label = ModelCapability.label(capability);
    String message;
    switch (capability) {
      case ModelCapability.image:
        await ref
            .read(imageGenerationConfigProvider.notifier)
            .setModel(name);
        message = '已把 $name 设为图片生成模型（生成图片 / 编辑图片工具使用）';
      case ModelCapability.audio:
        final lower = name.toLowerCase();
        final isTts =
            lower.contains('tts') ||
            lower.contains('text-to-speech') ||
            lower.contains('voice') ||
            lower.contains('speech') &&
                !lower.contains('to-text');
        if (isTts) {
          await ref
              .read(textToSpeechConfigProvider.notifier)
              .applyModel(name);
          message = '已把 $name 设为语音合成（TTS）模型';
        } else {
          await ref
              .read(speechToTextConfigProvider.notifier)
              .applyModel(name);
          message = '已把 $name 设为语音识别（STT）模型';
        }
      case ModelCapability.video:
        await ref
            .read(universalMediaConfigProvider.notifier)
            .applyMediaModel(UniversalMediaKind.video, name);
        message = '已把 $name 设为视频生成模型';
      case ModelCapability.music:
        await ref
            .read(universalMediaConfigProvider.notifier)
            .applyMediaModel(UniversalMediaKind.music, name);
        message = '已把 $name 设为音乐生成模型';
      default:
        message = '$name（$label）请在对应功能中配置使用';
    }
    if (!context.mounted) return;
    _showMessage(context, message);
  }

  Future<void> _switchModel(
    BuildContext context,
    WidgetRef ref, {
    required ChannelModelWithChannel target,
    required ChannelModelWithChannel? previous,
  }) async {
    try {
      final result = await switchConversationModel(
        ref: ref,
        modelId: target.channelModel.id,
        modelLabel: target.displayLabel,
        previousModelId: previous?.channelModel.id,
        previousModelLabel: previous?.displayLabel,
      );
      if (!context.mounted || !result.changed) return;
      _showMessage(
        context,
        result.recorded ? '已切换模型，记录已写入当前对话' : result.message,
      );
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '模型切换失败，当前会话保持不变，请重试');
    }
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }
}

const _kDefaultDreamingForegroundCheckInterval = Duration(minutes: 1);

@visibleForTesting
Duration dreamingForegroundCheckInterval =
    _kDefaultDreamingForegroundCheckInterval;

@visibleForTesting
void resetDreamingForegroundCheckIntervalForTesting() {
  dreamingForegroundCheckInterval = _kDefaultDreamingForegroundCheckInterval;
}

@visibleForTesting
Duration backgroundInterruptedPersistDelayForTesting = Duration.zero;

@visibleForTesting
void resetBackgroundInterruptedPersistDelayForTesting() {
  backgroundInterruptedPersistDelayForTesting = Duration.zero;
}

/// 响应式外壳：桌面端固定侧边栏，移动端 Drawer
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key});

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell>
    with WidgetsBindingObserver {
  static const _kDesktopBreakpoint = 720.0;
  final MethodChannelSimiDeepLinkService _deepLinkService =
      MethodChannelSimiDeepLinkService();
  bool _autoSelectingSession = false;
  Timer? _dreamingForegroundTimer;
  StreamSubscription<SimiDeepLink>? _deepLinkSubscription;
  List<String> _backgroundInterruptedSessionIds = const [];
  List<String> _networkInterruptedSessionIds = const [];
  Future<void>? _backgroundInterruptedPersistFuture;
  String? _lastPromptedDreamingFailedJobId;
  String? _lastNotifiedDreamingFailedDayKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDreamingForegroundTimer();
    _deepLinkSubscription = _deepLinkService.links.listen((link) {
      unawaited(_handleDeepLink(link));
    });
    // 首次启动时，如果没有会话则自动创建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupTasks());
    });
  }

  @override
  void dispose() {
    _dreamingForegroundTimer?.cancel();
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_deepLinkService.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startDreamingForegroundTimer();
      unawaited(
        _runDueDreamingIfNeeded().whenComplete(
          _showDreamingFailedJobPromptIfNeeded,
        ),
      );
      _showBackgroundInterruptedRetryPromptIfNeeded();
    } else {
      _dreamingForegroundTimer?.cancel();
      _dreamingForegroundTimer = null;
      final streamingSessionIds =
          _streamingSessionIdsForLifecycleCancellation();
      if (streamingSessionIds.isNotEmpty) {
        _backgroundInterruptedSessionIds = streamingSessionIds;
        final persistFuture = _persistBackgroundInterruptedSessions(
          streamingSessionIds,
        );
        _backgroundInterruptedPersistFuture = persistFuture;
        unawaited(
          persistFuture.whenComplete(() {
            if (identical(_backgroundInterruptedPersistFuture, persistFuture)) {
              _backgroundInterruptedPersistFuture = null;
            }
          }),
        );
        for (final sessionId in streamingSessionIds) {
          cancelStreaming(
            ref,
            sessionId,
            error: backgroundStreamingInterruptedMessage,
          );
        }
      }
    }
  }

  void _handleNetworkBecameOffline() {
    final streamingSessionIds = _streamingSessionIdsForLifecycleCancellation();
    if (streamingSessionIds.isEmpty) return;
    _networkInterruptedSessionIds = streamingSessionIds;
    for (final sessionId in streamingSessionIds) {
      cancelStreaming(
        ref,
        sessionId,
        error: networkStreamingInterruptedMessage,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text('网络连接断开，已停止生成，联网后可重试'),
        ),
      );
  }

  void _showNetworkInterruptedRetryPromptIfNeeded() {
    if (!mounted) return;
    final interruptedSessionIds = _networkInterruptedSessionIds;
    if (interruptedSessionIds.isEmpty) return;
    final retryableSessionIds = interruptedSessionIds
        .where(
          (sessionId) =>
              ref.read(streamStateProvider(sessionId)).error ==
              networkStreamingInterruptedMessage,
        )
        .toList();
    _networkInterruptedSessionIds = const [];
    if (retryableSessionIds.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text(
            _networkInterruptedRestoredSnackBarText(retryableSessionIds.length),
          ),
          action: SnackBarAction(
            label: _backgroundInterruptedRestoredSnackBarActionText(
              retryableSessionIds.length,
            ),
            onPressed: () =>
                _retryBackgroundInterruptedSessions(retryableSessionIds),
          ),
        ),
      );
  }

  String _networkInterruptedRestoredSnackBarText(int count) {
    if (count <= 1) {
      return '网络已恢复，可点“重试”继续';
    }
    return '网络已恢复，$count 个会话可点“重试全部”继续';
  }

  void _startDreamingForegroundTimer() {
    _dreamingForegroundTimer?.cancel();
    _dreamingForegroundTimer = Timer.periodic(dreamingForegroundCheckInterval, (
      _,
    ) {
      if (mounted) {
        _runDueDreamingIfNeeded();
      }
    });
  }

  Future<void> _runStartupTasks() async {
    await _autoSelectOrCreateSession();
    await _restorePersistedBackgroundInterruptedRetryIfNeeded();
    unawaited(
      _runDueDreamingIfNeeded().whenComplete(
        _showDreamingFailedJobPromptIfNeeded,
      ),
    );
    unawaited(_handleInitialDeepLinkIfNeeded());
  }

  Future<void> _handleInitialDeepLinkIfNeeded() async {
    try {
      final link = await _deepLinkService.getInitialLink();
      if (link == null || !mounted) return;
      await _handleDeepLink(link);
    } catch (_) {
      // 深度链接失败不影响正常启动。
    }
  }

  Future<void> _handleDeepLink(SimiDeepLink link) async {
    if (!mounted) return;
    switch (link.action) {
      case SimiDeepLinkAction.home:
        _popToHome();
        return;
      case SimiDeepLinkAction.newChat:
        _popToHome();
        await createNewSession(ref);
        if (!mounted) return;
        _showDeepLinkSnackBar('已通过链接新建会话');
        return;
      case SimiDeepLinkAction.settings:
        _popToHome();
        if (!mounted) return;
        await _pushDeepLinkRoute('/settings');
        return;
      case SimiDeepLinkAction.marketplace:
        _popToHome();
        if (!mounted) return;
        await _pushDeepLinkRoute('/marketplace');
        return;
      case SimiDeepLinkAction.session:
        final sessionId = link.sessionId;
        if (sessionId == null) return;
        final session = await ref
            .read(sessionDaoProvider)
            .getSession(sessionId);
        if (!mounted) return;
        if (session == null) {
          _showDeepLinkSnackBar('链接中的会话不存在或已删除');
          return;
        }
        _popToHome();
        ref.read(activeSessionIdProvider.notifier).state = session.id;
        refreshSessions(ref);
        _showDeepLinkSnackBar('已打开链接中的会话');
        return;
    }
  }

  Future<void> _pushDeepLinkRoute(String routeName) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).pushNamed(routeName);
  }

  void _popToHome() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  void _showDeepLinkSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _streamingSessionIdsForLifecycleCancellation() {
    final sessionIds = <String>[];
    void addIfStreaming(String? sessionId) {
      if (sessionId == null || sessionIds.contains(sessionId)) return;
      if (!ref.read(streamStateProvider(sessionId)).isStreaming) return;
      sessionIds.add(sessionId);
    }

    addIfStreaming(ref.read(activeSessionIdProvider));
    for (final session
        in ref.read(sessionsProvider).valueOrNull ?? const <Session>[]) {
      addIfStreaming(session.id);
    }
    return sessionIds;
  }

  Future<void> _persistBackgroundInterruptedSessions(
    List<String> sessionIds,
  ) async {
    try {
      if (backgroundInterruptedPersistDelayForTesting > Duration.zero) {
        await Future<void>.delayed(backgroundInterruptedPersistDelayForTesting);
      }
      final prefs = await SharedPreferences.getInstance();
      final persistedSessionIds = _readPersistedBackgroundInterruptedSessionIds(
        prefs,
      );
      for (final sessionId in sessionIds) {
        if (!persistedSessionIds.contains(sessionId)) {
          persistedSessionIds.add(sessionId);
        }
      }
      await prefs.setStringList(
        kBackgroundInterruptedSessionsStorageKey,
        persistedSessionIds,
      );
      await prefs.setString(
        kBackgroundInterruptedSessionStorageKey,
        sessionIds.first,
      );
    } catch (_) {
      // 持久化失败不能影响后台切出取消流式请求。
    }
  }

  Future<void> _restorePersistedBackgroundInterruptedRetryIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final interruptedSessionIds =
          _readPersistedBackgroundInterruptedSessionIds(prefs);
      if (interruptedSessionIds.isEmpty) return;
      if (!mounted) return;

      final restoredSessionIds = <String>[];
      final sessionDao = ref.read(sessionDaoProvider);
      for (final sessionId in interruptedSessionIds) {
        final interruptedSession = await sessionDao.getSession(sessionId);
        if (!mounted) return;
        if (interruptedSession == null) {
          continue;
        }
        restoredSessionIds.add(sessionId);
        ref.read(streamStateProvider(sessionId).notifier).state =
            const StreamState(error: backgroundStreamingInterruptedMessage);
      }

      await _clearPersistedBackgroundInterruptedSession();
      if (!mounted || restoredSessionIds.isEmpty) return;

      final primarySessionId = restoredSessionIds.first;
      if (ref.read(activeSessionIdProvider) != primarySessionId) {
        ref.read(activeSessionIdProvider.notifier).state = primarySessionId;
      }
      if (!mounted || ref.read(activeSessionIdProvider) != primarySessionId) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.fixed,
            content: Text(
              _backgroundInterruptedRestoredSnackBarText(
                restoredSessionIds.length,
              ),
            ),
            action: SnackBarAction(
              label: _backgroundInterruptedRestoredSnackBarActionText(
                restoredSessionIds.length,
              ),
              onPressed: () =>
                  _retryBackgroundInterruptedSessions(restoredSessionIds),
            ),
          ),
        );
    } catch (_) {
      // 恢复提示失败不能影响应用启动。
    }
  }

  String _backgroundInterruptedRestoredSnackBarText(int count) {
    if (count <= 1) {
      return '已恢复上次后台中断，可点“重试”继续';
    }
    return '已恢复 $count 个后台中断会话，可点“重试全部”继续';
  }

  String _backgroundInterruptedRestoredSnackBarActionText(int count) {
    if (count <= 1) {
      return '重试';
    }
    return '重试全部';
  }

  void _retryBackgroundInterruptedSessions(List<String> sessionIds) {
    for (final sessionId in sessionIds) {
      retryLastUserMessage(ref, sessionId: sessionId);
    }
  }

  List<String> _readPersistedBackgroundInterruptedSessionIds(
    SharedPreferences prefs,
  ) {
    final sessionIds = <String>[];
    void addSessionId(String? value) {
      final sessionId = value?.trim();
      if (sessionId == null ||
          sessionId.isEmpty ||
          sessionIds.contains(sessionId)) {
        return;
      }
      sessionIds.add(sessionId);
    }

    for (final sessionId
        in prefs.getStringList(kBackgroundInterruptedSessionsStorageKey) ??
            const <String>[]) {
      addSessionId(sessionId);
    }
    addSessionId(prefs.getString(kBackgroundInterruptedSessionStorageKey));
    return sessionIds;
  }

  void _showBackgroundInterruptedRetryPromptIfNeeded() {
    if (!mounted) return;
    final interruptedSessionIds = _backgroundInterruptedSessionIds;
    if (interruptedSessionIds.isEmpty) {
      return;
    }
    final retryableSessionIds = interruptedSessionIds
        .where(
          (sessionId) =>
              ref.read(streamStateProvider(sessionId)).error ==
              backgroundStreamingInterruptedMessage,
        )
        .toList();
    if (retryableSessionIds.isEmpty) {
      _backgroundInterruptedSessionIds = const [];
      return;
    }
    _backgroundInterruptedSessionIds = const [];
    unawaited(_clearPersistedBackgroundInterruptedSession());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text(
            _backgroundInterruptedResumedSnackBarText(
              retryableSessionIds.length,
            ),
          ),
          action: SnackBarAction(
            label: _backgroundInterruptedRestoredSnackBarActionText(
              retryableSessionIds.length,
            ),
            onPressed: () =>
                _retryBackgroundInterruptedSessions(retryableSessionIds),
          ),
        ),
      );
  }

  String _backgroundInterruptedResumedSnackBarText(int count) {
    if (count <= 1) {
      return '已停止后台生成，可点“重试”继续';
    }
    return '已停止 $count 个后台生成，可点“重试全部”继续';
  }

  Future<void> _showDreamingFailedJobPromptIfNeeded() async {
    try {
      final failedJob = await ref.read(latestFailedDreamingJobProvider.future);
      if (!mounted || failedJob == null) return;
      if (_lastPromptedDreamingFailedJobId == failedJob.id) return;
      _lastPromptedDreamingFailedJobId = failedJob.id;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: const Text('上次 Dreaming 失败，可到设置页重试'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () {
              if (!mounted) return;
              unawaited(
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed('/settings'),
              );
            },
          ),
        ),
      );
    } catch (_) {
      // Dreaming 失败提示读取失败不能影响主聊天入口。
    }
  }

  Future<void> _clearPersistedBackgroundInterruptedSession() async {
    final pendingPersist = _backgroundInterruptedPersistFuture;
    if (pendingPersist != null) {
      try {
        await pendingPersist;
      } catch (_) {
        // 即使上一次 marker 写入失败，也继续执行清理。
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kBackgroundInterruptedSessionStorageKey);
      await prefs.remove(kBackgroundInterruptedSessionsStorageKey);
    } catch (_) {
      // 清理失败只会导致下次启动再次提示，不影响当前恢复。
    }
  }

  Future<void> _autoSelectOrCreateSession() async {
    if (_autoSelectingSession || ref.read(activeSessionIdProvider) != null) {
      return;
    }
    _autoSelectingSession = true;
    try {
      final sessions = await ref.read(sessionsProvider.future);
      if (!mounted || ref.read(activeSessionIdProvider) != null) return;
      if (sessions.isEmpty) {
        await createNewSession(ref);
      } else {
        ref.read(activeSessionIdProvider.notifier).state = sessions.first.id;
      }
    } finally {
      _autoSelectingSession = false;
    }
  }

  Future<void> _runDueDreamingIfNeeded() async {
    try {
      await retryPendingAssistantReflection(ref);
    } catch (_) {
      // 待处理反思重试失败不能影响新的 Dreaming 检查；pending 会保留供下次恢复。
    }
    if (!mounted) return;
    try {
      final digest = await maybeRunDueDreaming(ref);
      if (!mounted) return;
      if (digest != null && digest.hasContent) {
        var profileProposalCount = 0;
        try {
          final proposal = await proposeUserProfileChanges(
            ref,
            reason: 'profile_proposal',
          );
          profileProposalCount = proposal?.diff.items.length ?? 0;
        } catch (_) {
          // 画像候选生成失败也不影响 Dreaming 完成通知。
        }
        if (!mounted) return;
        try {
          await runAssistantReflection(
            ref,
            digest: digest,
            pendingProfileProposalCount: profileProposalCount,
          );
        } catch (_) {
          // 本地反思失败不能影响 Dreaming 完成通知。
        }
        if (!mounted) return;
        await dreamingDigestCompleteNotifier(
          dayKey: digest.dayKey,
          originalMessageCount: digest.originalMessageCount,
          totalOriginalMessageCount: digest.totalOriginalMessageCount,
          memoryCandidateCount: digest.memoryCandidates.length,
          profileProposalCount: profileProposalCount,
        );
      }
    } catch (_) {
      if (!mounted) return;
      await _notifyDreamingFailedIfNeeded();
    }
  }

  Future<void> _notifyDreamingFailedIfNeeded() async {
    try {
      ref.invalidate(latestFailedDreamingJobProvider);
      final failedJob = await ref.read(latestFailedDreamingJobProvider.future);
      if (!mounted || failedJob == null) return;
      if (_lastNotifiedDreamingFailedDayKey == failedJob.dayKey) return;
      _lastNotifiedDreamingFailedDayKey = failedJob.dayKey;
      await dreamingDigestFailedNotifier(dayKey: failedJob.dayKey);
    } catch (_) {
      // 前台到期整理失败通知也不能影响聊天主链路；用户仍可在设置页手动重试。
    }
  }

  @override
  Widget build(BuildContext context) {
    // watch 以保持响应式（子组件依赖这些 provider）
    ref.watch(sessionsProvider);
    ref.watch(activeSessionIdProvider);
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == true && !next) {
        _handleNetworkBecameOffline();
      } else if (previous == false && next) {
        _showNetworkInterruptedRetryPromptIfNeeded();
      }
    });

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewSessionIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyK,
        ): const _SearchIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyK,
        ): const _SearchIntent(),
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
          const SizedBox(width: 280, child: Sidebar()),
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
      drawer: const Drawer(child: SafeArea(child: Sidebar())),
      body: const ChatPage(),
    );
  }

  /// AppBar 标题：会话名 + 当前模型（桌面端与移动端统一可切换）。
  /// 标题宽度继承 AppBar 的可用空间，模型胶囊本身有上限，避免窄屏被
  /// 长渠道名或模型名撑出横向溢出。
  Widget _buildChatTitle(
    BuildContext context,
    AsyncValue<Session?> activeSession,
  ) {
    final title =
        activeSession.whenOrNull(data: (session) => session?.title) ??
        'SimiAIChat';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          const ChatModelSelector(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildChatAppBar(
    BuildContext context,
    WidgetRef ref, {
    bool showMenuButton = false,
  }) {
    final activeSession = ref.watch(activeSessionProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);

    return AppBar(
      // 会话名位于 44dp 模型控件上方，保留 ChatGPT 风格的两行顶部区域，
      // 同时不压缩移动端模型选择器的可访问触达范围。
      toolbarHeight: 72,
      leading: showMenuButton
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: _buildChatTitle(context, activeSession),
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
