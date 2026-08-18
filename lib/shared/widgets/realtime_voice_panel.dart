import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/realtime_voice_models.dart';
import '../providers/realtime_voice_provider.dart';

/// ChatGPT 风格的 Realtime Voice 面板。
///
/// 面板支持 Realtime WebSocket 会话和文字 fallback；原生 PCM bridge 可用时，
/// 也会提供直接的麦克风采集与扬声器播放。Android 当前通过
/// AudioRecord/AudioTrack 接入；非 Android 取决于对应平台 bridge，未连接时
/// 不会启动 PCM。这里的 UI 测试只覆盖本地状态与注入的边界，不证明真实
/// Realtime WebSocket 或云端音频 E2E。
class RealtimeVoicePanel extends ConsumerStatefulWidget {
  const RealtimeVoicePanel({super.key});

  @override
  ConsumerState<RealtimeVoicePanel> createState() => _RealtimeVoicePanelState();
}

class _RealtimeVoicePanelState extends ConsumerState<RealtimeVoicePanel> {
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _voiceController = TextEditingController();
  final _protocolPrefixController = TextEditingController();
  final _tokenController = TextEditingController();
  final _textController = TextEditingController();
  bool _formDirty = false;
  bool _saving = false;
  bool _sendingText = false;
  RealtimeVoiceProvider _provider = RealtimeVoiceProvider.openAi;
  RealtimeVoiceAuthMode _authMode = RealtimeVoiceAuthMode.bearer;

  @override
  void initState() {
    super.initState();
    _loadForm(ref.read(realtimeVoiceProvider).config);
    unawaited(
      ref.read(realtimeVoiceProvider.notifier).ready.then((_) {
        if (!mounted || _formDirty) return;
        _loadForm(ref.read(realtimeVoiceProvider).config);
      }),
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _voiceController.dispose();
    _protocolPrefixController.dispose();
    _tokenController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _loadForm(RealtimeVoiceConfig config) {
    _provider = config.provider;
    _authMode = config.provider == RealtimeVoiceProvider.geminiLive
        ? RealtimeVoiceAuthMode.apiKeyHeader
        : config.authMode == RealtimeVoiceAuthMode.apiKeyHeader
        ? RealtimeVoiceAuthMode.bearer
        : config.authMode;
    _endpointController.text = config.endpoint;
    _modelController.text = config.model;
    _voiceController.text = config.voice;
    _protocolPrefixController.text = config.protocolPrefix ?? '';
    _tokenController.clear();
  }

  RealtimeVoiceConfig _formConfig(RealtimeVoiceConfig current) {
    final token = _tokenController.text.trim();
    return current.copyWith(
      provider: _provider,
      endpoint: _endpointController.text.trim(),
      model: _modelController.text.trim(),
      voice: _voiceController.text.trim(),
      authMode: _provider == RealtimeVoiceProvider.geminiLive
          ? RealtimeVoiceAuthMode.apiKeyHeader
          : _authMode,
      token: token.isEmpty ? null : token,
      protocolPrefix: _protocolPrefixController.text.trim(),
    );
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(realtimeVoiceProvider.notifier);
      await notifier.saveConfig(
        _formConfig(ref.read(realtimeVoiceProvider).config),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _formDirty = false;
        });
        _showMessage('实时语音配置已保存');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showMessage(_safeMessage(error));
      }
    }
  }

  Future<void> _connect() async {
    try {
      await ref.read(realtimeVoiceProvider.notifier).connect();
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    }
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(realtimeVoiceProvider.notifier).disconnect();
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    }
  }

  Future<void> _cancelResponse() async {
    try {
      await ref.read(realtimeVoiceProvider.notifier).cancelResponse();
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    }
  }

  Future<void> _startNativeAudio() async {
    try {
      await ref.read(realtimeVoiceProvider.notifier).startNativeAudio();
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    }
  }

  Future<void> _stopNativeAudio() async {
    try {
      await ref.read(realtimeVoiceProvider.notifier).stopNativeAudio();
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sendingText) return;
    setState(() => _sendingText = true);
    try {
      await ref.read(realtimeVoiceProvider.notifier).sendText(text);
      if (mounted) {
        _textController.clear();
      }
    } catch (error) {
      if (mounted) _showMessage(_safeMessage(error));
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _safeMessage(Object error) {
    if (error is RealtimeVoiceSessionException) return error.message;
    return error.toString().replaceFirst('FormatException: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(realtimeVoiceProvider);
    final scheme = Theme.of(context).colorScheme;
    final isConnected = state.isConnected;
    final isBusy = state.isBusy;

    return Material(
      color: scheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, state),
                const SizedBox(height: 12),
                _buildStatusCard(state, scheme),
                const SizedBox(height: 12),
                _buildConversationCard(state, scheme),
                const SizedBox(height: 12),
                if (isConnected) ...[
                  _buildTextComposer(state, scheme),
                  const SizedBox(height: 12),
                ],
                _buildCaptureBoundary(state, scheme),
                const SizedBox(height: 12),
                _buildConfigurationForm(state, scheme),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('realtime-voice-connect-button'),
                        onPressed:
                            isBusy || isConnected || !state.config.isConfigured
                            ? null
                            : _connect,
                        icon: Icon(
                          isBusy
                              ? Icons.hourglass_top
                              : Icons.wifi_tethering_outlined,
                        ),
                        label: Text(isBusy ? '连接中…' : '连接实时语音'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      ),
                    ),
                    if (isConnected) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey(
                            'realtime-voice-disconnect-button',
                          ),
                          onPressed: _disconnect,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('断开'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (isConnected) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('realtime-voice-cancel-button'),
                    onPressed: _cancelResponse,
                    icon: const Icon(Icons.close),
                    label: const Text('停止当前回答'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ),
                ],
                if (!isConnected && !isBusy && !state.config.isConfigured) ...[
                  const SizedBox(height: 6),
                  Text(
                    '请先填写并保存 endpoint、模型和凭据，再连接实时语音。',
                    key: const ValueKey(
                      'realtime-voice-connect-disabled-reason',
                    ),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.errorMessage!,
                    key: const ValueKey('realtime-voice-error'),
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ],
                if (isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    '连接已建立；文本消息会通过当前 Realtime WebSocket 发送。',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, RealtimeVoiceState state) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.graphic_eq_outlined, color: scheme.primary),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '实时语音对话',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text('ChatGPT 风格的连接、转写与回答状态', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('realtime-voice-clear-button'),
          tooltip: '清空转写',
          onPressed: state.isConnected
              ? ref.read(realtimeVoiceProvider.notifier).clearTranscript
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
      ],
    );
  }

  Widget _buildStatusCard(RealtimeVoiceState state, ColorScheme scheme) {
    final stateLabel = switch (state.sessionState) {
      RealtimeVoiceSessionState.idle => '未连接',
      RealtimeVoiceSessionState.connecting => '连接中',
      RealtimeVoiceSessionState.connected => '已连接',
      RealtimeVoiceSessionState.closing => '正在断开',
      RealtimeVoiceSessionState.cancelling => '正在取消',
      RealtimeVoiceSessionState.closed => '已断开',
      RealtimeVoiceSessionState.cancelled => '已取消',
      RealtimeVoiceSessionState.failed => '连接失败',
    };
    final color = state.isConnected
        ? Colors.green
        : state.sessionState == RealtimeVoiceSessionState.failed
        ? scheme.error
        : scheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$stateLabel · ${state.config.providerLabel}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: Text(
                state.config.statusLabel,
                textAlign: TextAlign.end,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationCard(RealtimeVoiceState state, ColorScheme scheme) {
    final input = state.inputTranscript.trim();
    final output = state.outputText.trim().isNotEmpty
        ? state.outputText.trim()
        : state.outputTranscript.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '对话内容',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _transcriptLine(
              label: '你',
              text: input.isEmpty ? '等待语音输入转写…' : input,
              color: scheme.primary,
            ),
            const SizedBox(height: 8),
            _transcriptLine(
              label: '助手',
              text: output.isEmpty ? '等待助手回答…' : output,
              color: scheme.tertiary,
            ),
            if (state.receivedAudioBytes > 0) ...[
              const SizedBox(height: 8),
              Text(
                _audioFrameStatus(state),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _audioFrameStatus(RealtimeVoiceState state) {
    final bytes = state.receivedAudioBytes;
    if (!state.isConnected) {
      return '已收到 $bytes bytes 音频帧；当前未连接 Realtime WebSocket，未进入原生播放队列；连接后需要开启原生 PCM 才能播放。';
    }
    if (state.nativeAudioActive) {
      return '已收到 $bytes bytes 音频帧，已交给原生播放队列。';
    }
    return '已收到 $bytes bytes 音频帧；当前未开启原生 PCM，需要开启后才能播放。';
  }

  Widget _transcriptLine({
    required String label,
    required String text,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: SelectableText(text)),
      ],
    );
  }

  Widget _buildTextComposer(RealtimeVoiceState state, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('realtime-voice-text-input'),
              controller: _textController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '输入文字，让实时助手回答…',
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => unawaited(_sendText()),
            ),
          ),
          IconButton(
            key: const ValueKey('realtime-voice-send-text-button'),
            tooltip: '发送文字',
            onPressed: state.isConnected && !_sendingText ? _sendText : null,
            icon: _sendingText
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBoundary(RealtimeVoiceState state, ColorScheme scheme) {
    final isConnected = state.isConnected;
    final isActive = state.nativeAudioActive;
    final message = !isConnected
        ? '当前未连接 Realtime WebSocket；连接后才可尝试开启原生 PCM。Android 已接入 AudioRecord/AudioTrack，非 Android 取决于对应平台支持。普通麦克风按钮仍走录音文件 → STT → 聊天流程。'
        : isActive
        ? '原生 PCM 麦克风已开启，输入会直接发送到当前 WebSocket；收到的 PCM 音频已交给原生播放队列。Android 使用 AudioRecord/AudioTrack；非 Android 取决于对应平台支持。'
        : '当前已连接但未开启原生 PCM；在支持的平台上需要开启后才能播放收到的 PCM。Android 已接入 AudioRecord/AudioTrack，非 Android 取决于对应平台支持。普通麦克风按钮仍走录音文件 → STT → 聊天流程。';
    return Container(
      key: const ValueKey('realtime-voice-capture-boundary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isActive ? Icons.mic : Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  key: const ValueKey('realtime-voice-capture-message'),
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
          if (state.nativeAudioError != null) ...[
            const SizedBox(height: 6),
            Text(
              state.nativeAudioError!,
              key: const ValueKey('realtime-voice-native-audio-error'),
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          if (isConnected) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: isActive
                  ? OutlinedButton.icon(
                      key: const ValueKey('realtime-voice-stop-native-audio'),
                      onPressed: _stopNativeAudio,
                      icon: const Icon(Icons.mic_off_outlined),
                      label: const Text('停止实时麦克风'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    )
                  : FilledButton.tonalIcon(
                      key: const ValueKey('realtime-voice-start-native-audio'),
                      onPressed: _startNativeAudio,
                      icon: const Icon(Icons.mic_none_outlined),
                      label: const Text('开始实时麦克风'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _defaultEndpointFor(RealtimeVoiceProvider provider) =>
      switch (provider) {
        RealtimeVoiceProvider.openAi => kDefaultRealtimeVoiceOpenAiEndpoint,
        RealtimeVoiceProvider.xAi => kDefaultRealtimeVoiceXaiEndpoint,
        RealtimeVoiceProvider.geminiLive => kDefaultRealtimeVoiceGeminiEndpoint,
        RealtimeVoiceProvider.custom => kDefaultRealtimeVoiceOpenAiEndpoint,
        RealtimeVoiceProvider.simiRouter =>
          kDefaultRealtimeVoiceSimiRouterEndpoint,
      };

  String _defaultModelFor(RealtimeVoiceProvider provider) => switch (provider) {
    RealtimeVoiceProvider.openAi => kDefaultRealtimeVoiceOpenAiModel,
    RealtimeVoiceProvider.xAi => kDefaultRealtimeVoiceXaiModel,
    RealtimeVoiceProvider.geminiLive => kDefaultRealtimeVoiceGeminiModel,
    RealtimeVoiceProvider.custom => kDefaultRealtimeVoiceOpenAiModel,
    RealtimeVoiceProvider.simiRouter => '',
  };

  String _defaultVoiceFor(RealtimeVoiceProvider provider) => switch (provider) {
    RealtimeVoiceProvider.geminiLive => kDefaultRealtimeVoiceGeminiVoice,
    _ => kDefaultRealtimeVoiceVoice,
  };

  List<DropdownMenuItem<RealtimeVoiceAuthMode>> _authModeItems() {
    if (_provider == RealtimeVoiceProvider.geminiLive) {
      return const [
        DropdownMenuItem(
          value: RealtimeVoiceAuthMode.apiKeyHeader,
          child: Text('x-goog-api-key header'),
        ),
      ];
    }
    return const [
      DropdownMenuItem(
        value: RealtimeVoiceAuthMode.bearer,
        child: Text('Bearer API Key'),
      ),
      DropdownMenuItem(
        value: RealtimeVoiceAuthMode.ephemeral,
        child: Text('Ephemeral token'),
      ),
    ];
  }

  Widget _buildConfigurationForm(RealtimeVoiceState state, ColorScheme scheme) {
    return ExpansionTile(
      key: const ValueKey('realtime-voice-configuration'),
      initiallyExpanded: !state.config.isConfigured,
      title: const Text('连接配置'),
      subtitle: Text(state.config.safeSummary),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      children: [
        DropdownButtonFormField<RealtimeVoiceProvider>(
          key: ValueKey('realtime-voice-provider-field-${_provider.name}'),
          initialValue: _provider,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '服务商'),
          items: const [
            DropdownMenuItem(
              value: RealtimeVoiceProvider.openAi,
              child: Text('OpenAI Realtime'),
            ),
            DropdownMenuItem(
              value: RealtimeVoiceProvider.xAi,
              child: Text('xAI Realtime'),
            ),
            DropdownMenuItem(
              value: RealtimeVoiceProvider.geminiLive,
              child: Text('Gemini Live'),
            ),
            DropdownMenuItem(
              value: RealtimeVoiceProvider.custom,
              child: Text('自定义 OpenAI-compatible'),
            ),
            DropdownMenuItem(
              value: RealtimeVoiceProvider.simiRouter,
              child: Text('SimiRouter 中转站'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _formDirty = true;
              _provider = value;
              if (_endpointController.text.trim().isEmpty ||
                  {
                    kDefaultRealtimeVoiceOpenAiEndpoint,
                    kDefaultRealtimeVoiceXaiEndpoint,
                    kDefaultRealtimeVoiceGeminiEndpoint,
                  }.contains(_endpointController.text)) {
                _endpointController.text = _defaultEndpointFor(value);
              }
              if (_modelController.text.trim().isEmpty ||
                  {
                    kDefaultRealtimeVoiceOpenAiModel,
                    kDefaultRealtimeVoiceXaiModel,
                    kDefaultRealtimeVoiceGeminiModel,
                  }.contains(_modelController.text)) {
                _modelController.text = _defaultModelFor(value);
              }
              if (_voiceController.text.trim().isEmpty ||
                  {
                    kDefaultRealtimeVoiceVoice,
                    kDefaultRealtimeVoiceGeminiVoice,
                  }.contains(_voiceController.text)) {
                _voiceController.text = _defaultVoiceFor(value);
              }
              _authMode = value == RealtimeVoiceProvider.geminiLive
                  ? RealtimeVoiceAuthMode.apiKeyHeader
                  : _authMode == RealtimeVoiceAuthMode.apiKeyHeader
                  ? RealtimeVoiceAuthMode.bearer
                  : _authMode;
            });
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('realtime-voice-endpoint-field'),
          controller: _endpointController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'WebSocket endpoint',
            hintText: 'wss://…',
          ),
          onChanged: (_) => setState(() => _formDirty = true),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('realtime-voice-model-field'),
                controller: _modelController,
                decoration: const InputDecoration(labelText: '模型'),
                onChanged: (_) => setState(() => _formDirty = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('realtime-voice-voice-field'),
                controller: _voiceController,
                decoration: const InputDecoration(labelText: '音色'),
                onChanged: (_) => setState(() => _formDirty = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<RealtimeVoiceAuthMode>(
          key: ValueKey('realtime-voice-auth-mode-field-${_authMode.name}'),
          initialValue: _authMode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '凭据方式'),
          items: _authModeItems(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _authMode = value;
              _formDirty = true;
            });
          },
        ),
        if (_provider == RealtimeVoiceProvider.geminiLive) ...[
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Gemini Live 使用 x-goog-api-key header；不会把 API key 放进 WebSocket URL query。',
              key: ValueKey('realtime-voice-gemini-auth-hint'),
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('realtime-voice-token-field'),
          controller: _tokenController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: state.config.hasToken ? '凭据（留空保持已保存凭据）' : '凭据',
            hintText: '不会显示或写入诊断日志',
          ),
          onChanged: (_) => setState(() => _formDirty = true),
        ),
        if (_authMode == RealtimeVoiceAuthMode.ephemeral) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('realtime-voice-protocol-prefix-field'),
            controller: _protocolPrefixController,
            decoration: const InputDecoration(
              labelText: 'Ephemeral protocol prefix（可选）',
            ),
            onChanged: (_) => setState(() => _formDirty = true),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const ValueKey('realtime-voice-save-button'),
            onPressed: _saving ? null : _saveConfig,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '保存配置'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ),
      ],
    );
  }
}
