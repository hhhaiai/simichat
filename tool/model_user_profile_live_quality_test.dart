import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/openai_chat_protocol.dart';
import 'package:ai_chat_app/core/memory/dreaming_service.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/model_user_profile_service.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_reflection_live_config.dart';

void main() {
  test(
    'remote OpenAI-compatible model produces safe grounded profile candidates',
    () async {
      final configPath = Platform.environment['MODEL_CONFIG_FILE'];
      if (configPath == null || configPath.trim().isEmpty) {
        fail(
          'MODEL_CONFIG_FILE is required for the remote profile quality gate',
        );
      }
      final config = await loadModelReflectionLiveConfig(
        File(configPath.trim()),
      );
      final runCount =
          int.tryParse(
            Platform.environment['SIMICHAT_LIVE_PROFILE_MODEL_RUNS'] ?? '3',
          ) ??
          0;
      if (runCount < 1 || runCount > 5) {
        fail('SIMICHAT_LIVE_PROFILE_MODEL_RUNS must be between 1 and 5');
      }

      final results = <Map<String, Object>>[];
      for (var index = 0; index < runCount; index++) {
        results.add(
          await _runQualityCheck(
            config: config,
            runIndex: index + 1,
            now: DateTime.utc(2026, 7, 14 + index, 22),
          ),
        );
      }

      stdout.writeln(
        jsonEncode({
          'marker': 'SIMICHAT_LIVE_MODEL_PROFILE_QUALITY_SUMMARY_OK',
          'model': config.model,
          'runs': results.length,
          'elapsedMs': results.fold<int>(
            0,
            (sum, result) => sum + (result['elapsedMs']! as int),
          ),
          'attempts': results
              .map((result) => result['attempts']! as int)
              .toList(growable: false),
          'additionalSignals': results
              .map((result) => result['additionalSignals']! as int)
              .toList(growable: false),
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<Map<String, Object>> _runQualityCheck({
  required ModelReflectionLiveConfig config,
  required int runIndex,
  required DateTime now,
}) async {
  final digest = _profileDigest(now, runIndex);
  final localCandidate = _localCandidate(now);
  final service = const ModelUserProfileService();
  final stopwatch = Stopwatch()..start();

  late final ({String content, int attempts}) remote;
  try {
    remote = await _fetchRemoteProfile(
      config: config,
      messages: [
        AiMessage(
          role: 'user',
          content: service.buildUserPrompt(
            digest: digest,
            localCandidate: localCandidate,
          ),
        ),
      ],
      systemPrompt: service.systemPrompt,
    );
  } finally {
    stopwatch.stop();
  }

  final enhanced = service.enhanceFromResponse(
    digest: digest,
    localCandidate: localCandidate,
    response: remote.content,
  );
  final output = enhanced.toMarkdown();
  final additionalSignals = _additionalSignalCount(localCandidate, enhanced);

  expect(additionalSignals, greaterThan(0));
  expect(
    additionalSignals,
    lessThanOrEqualTo(kModelUserProfileMaxAdditionalItems),
  );
  expect(enhanced.preferences, containsAll(localCandidate.preferences));
  expect(enhanced.goals, containsAll(localCandidate.goals));
  expect(enhanced.tasks, containsAll(localCandidate.tasks));
  expect(enhanced.profileFacts, localCandidate.profileFacts);
  expect(enhanced.sourceCount, localCandidate.sourceCount);
  expect(enhanced.digestDayKey, localCandidate.digestDayKey);
  expect(output, isNot(contains('sk-live-profile-secret')));
  expect(output, isNot(contains('profile.example.test')));
  expect(output, isNot(contains('/Users/live/profile.txt')));
  expect(output, isNot(contains('焦虑症')));
  expect(output, isNot(contains('用户是移动端工程师')));
  expect(output, isNot(contains('已修改正式画像')));
  expect(
    [
      '移动端',
      '智能助理',
      'Dreaming',
      'Reflection',
      '验证',
      '结论',
      '证据',
    ].any(output.contains),
    isTrue,
  );

  final result = <String, Object>{
    'marker': 'SIMICHAT_LIVE_MODEL_PROFILE_QUALITY_OK',
    'model': config.model,
    'run': runIndex,
    'dayKey': digest.dayKey,
    'elapsedMs': stopwatch.elapsedMilliseconds,
    'attempts': remote.attempts,
    'responseChars': remote.content.length,
    'additionalSignals': additionalSignals,
  };
  stdout.writeln(jsonEncode(result));
  return result;
}

Future<({String content, int attempts})> _fetchRemoteProfile({
  required ModelReflectionLiveConfig config,
  required List<AiMessage> messages,
  required String systemPrompt,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    final cancelToken = CancelToken();
    try {
      final result =
          await OpenAiChatProtocol.fetchMessageOnce(
            baseUrl: config.baseUrl,
            apiKey: config.apiKey,
            model: config.model,
            messages: messages,
            systemPrompt: systemPrompt,
            cancelToken: cancelToken,
          ).timeout(
            kModelUserProfileTimeout,
            onTimeout: () {
              cancelToken.cancel('live model profile timeout');
              throw TimeoutException('Remote model profile request timed out');
            },
          );
      if (result.content.trim().isEmpty) {
        throw const ModelUserProfileFormatException(
          'Remote model returned empty profile content',
        );
      }
      return (content: result.content, attempts: attempt);
    } catch (error) {
      lastError = error;
      if (attempt == 3 || !_isRetryableFailure(error)) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }
  throw StateError('Remote model profile quality request failed: $lastError');
}

bool _isRetryableFailure(Object error) {
  if (error is TimeoutException || error is ModelUserProfileFormatException) {
    return true;
  }
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  return status == null ||
      status == 401 ||
      status == 408 ||
      status == 429 ||
      status >= 500;
}

int _additionalSignalCount(UserProfile local, UserProfile enhanced) {
  int additions(List<String> before, List<String> after) {
    final keys = before.map((item) => item.toLowerCase()).toSet();
    return after.where((item) => !keys.contains(item.toLowerCase())).length;
  }

  return additions(local.preferences, enhanced.preferences) +
      additions(local.goals, enhanced.goals) +
      additions(local.tasks, enhanced.tasks) +
      additions(local.styleSignals, enhanced.styleSignals) +
      additions(local.scheduleSignals, enhanced.scheduleSignals) +
      additions(local.keywords, enhanced.keywords);
}

UserProfile _localCandidate(DateTime now) {
  return UserProfile(
    updatedAt: now,
    sourceCount: 3,
    preferences: const ['我希望回答先给结论，再给可验证证据'],
    goals: const ['我的目标是把 SimiChat 做成移动端稳定的智能助理'],
    tasks: const ['下一步继续验证 Android 跨日自然调度和 iOS BGTask'],
    profileFacts: const [],
    styleSignals: const [],
    scheduleSignals: const [],
    keywords: const ['SimiChat'],
    digestDayKey: now.toIso8601String().substring(0, 10),
  );
}

DreamingDigest _profileDigest(DateTime now, int runIndex) {
  KeyPointMemoryItem memory(String id, String category, String content) {
    return KeyPointMemoryItem(
      id: id,
      sessionId: 'profile-quality-$runIndex',
      sourceMessageId: 'source-$id',
      category: category,
      content: content,
      keywords: extractMemoryKeywords(content),
      confidence: 0.9,
      createdAt: now,
      updatedAt: now,
    );
  }

  return DreamingDigest(
    day: now,
    generatedAt: now,
    sessionCount: 1,
    originalMessageCount: 72,
    userMessageCount: 36,
    assistantMessageCount: 36,
    sessions: [
      DreamingSessionDigest(
        sessionId: 'profile-quality-$runIndex',
        title: '移动端智能助理画像增量质量',
        messageCount: 72,
        userMessageCount: 36,
        assistantMessageCount: 36,
        highlights: const [
          '移动端 Dreaming 和 Reflection 已有本地规则与后台编排，仍需跨日和 iOS 系统执行验证。',
          '用户要求模型画像只能生成待确认候选，不能直接修改正式画像。',
          'Bearer sk-live-profile-secret https://profile.example.test/private /Users/live/profile.txt',
        ],
        firstMessageAt: now.subtract(const Duration(hours: 4)),
        lastMessageAt: now,
        lastMessageRole: 'assistant',
      ),
    ],
    memoryCandidates: [
      memory('preference', 'preference', '我希望回答先给结论，再给可验证证据'),
      memory('goal', 'goal', '我的目标是把 SimiChat 做成移动端稳定的智能助理'),
      memory('task', 'task', '下一步继续验证 Android 跨日自然调度和 iOS BGTask'),
    ],
    keywords: const ['SimiChat', 'Dreaming', 'Reflection', '移动端'],
    elapsedMs: 12,
  );
}
