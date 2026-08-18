import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/media/audio_transcript_archive.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

typedef AttachmentImageBuilder =
    Widget Function(BuildContext context, MessageAttachmentView attachment);

class MessageAttachmentView {
  final String? attachmentId;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String? localPath;
  final AudioTranscriptStatus? audioTranscriptStatus;
  final VoidCallback? onOpenAudioTranscript;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onOpenImage;
  final VoidCallback? onDownload;
  final bool isPlayingAudio;

  /// 图片长按回调（如“编辑此图”）。为 null 时图片无长按交互。
  final VoidCallback? onEditImage;

  const MessageAttachmentView({
    this.attachmentId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    this.localPath,
    this.audioTranscriptStatus,
    this.onOpenAudioTranscript,
    this.onPlayAudio,
    this.onOpenImage,
    this.onDownload,
    this.isPlayingAudio = false,
    this.onEditImage,
  });

  bool get isImage => fileType == 'image';

  bool get isAudio => fileType == 'audio';

  bool get isVideo => fileType == 'video';

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;

  bool get canOpenAudioTranscript => isAudio && onOpenAudioTranscript != null;

  bool get canEditImage => isImage && onEditImage != null;
}

/// ChatGPT-style message row: assistant answers are plain content blocks;
/// user messages are compact right-aligned bubbles.
class MessageBubble extends StatelessWidget {
  final String? messageId;
  final String role;
  final String content;
  final String? thinkingContent;
  final int tokens;
  final int? responseMs;
  final bool isUser;
  final VoidCallback? onRetry;

  /// 新的 retry 路径携带被点击的 assistant message ID；旧 [onRetry] 保留
  /// 给外部通用气泡调用方兼容。
  final ValueChanged<String>? onRetryMessage;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;
  final VoidCallback? onStopSpeaking;
  final bool isSpeaking;
  final bool isPreparingSpeech;
  final VoidCallback? onFork;
  final String? modelName;
  final List<MessageAttachmentView> attachments;
  final AttachmentImageBuilder? attachmentImageBuilder;

  const MessageBubble({
    super.key,
    this.messageId,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.tokens = 0,
    this.responseMs,
    required this.isUser,
    this.onRetry,
    this.onRetryMessage,
    this.onCopy,
    this.onSpeak,
    this.onStopSpeaking,
    this.isSpeaking = false,
    this.isPreparingSpeech = false,
    this.onFork,
    this.modelName,
    this.attachments = const [],
    this.attachmentImageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kChatContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: isUser
              ? _buildUserMessage(context)
              : _buildAssistantMessage(context),
        ),
      ),
    );
  }

  Widget _buildUserMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (content.isNotEmpty) LatexMarkdownWidget(data: content),
                if (attachments.isNotEmpty) ...[
                  if (content.isNotEmpty) const SizedBox(height: 10),
                  _AttachmentList(
                    attachments: attachments,
                    imageBuilder: attachmentImageBuilder,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistantMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSpeak =
        onSpeak != null && content.trim().isNotEmpty && !isPreparingSpeech;
    final canStopSpeaking = onStopSpeaking != null && isSpeaking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (modelName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              modelName!,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (thinkingContent != null && thinkingContent!.isNotEmpty)
          _ThinkingBlock(content: thinkingContent!),
        if (content.trim().isNotEmpty) LatexMarkdownWidget(data: content),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _AttachmentList(
            attachments: attachments,
            imageBuilder: attachmentImageBuilder,
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            _IconActionButton(
              icon: Icons.copy_all_outlined,
              tooltip: '复制',
              onTap: () {
                if (onCopy != null) {
                  onCopy!();
                } else {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            _IconActionButton(
              icon: Icons.refresh,
              tooltip: '重新生成',
              onTap: onRetryMessage != null && messageId != null
                  ? () => onRetryMessage!(messageId!)
                  : onRetry,
            ),
            if (isPreparingSpeech)
              const _IconActionButton(
                icon: Icons.hourglass_top_outlined,
                tooltip: '正在生成语音',
                onTap: null,
              )
            else if (canStopSpeaking)
              _IconActionButton(
                icon: Icons.stop_circle_outlined,
                tooltip: '停止播报',
                onTap: onStopSpeaking,
              )
            else if (canSpeak)
              _IconActionButton(
                icon: Icons.volume_up_outlined,
                tooltip: '语音播报',
                onTap: onSpeak,
              ),
            if (onFork != null)
              _IconActionButton(
                icon: Icons.call_split,
                tooltip: '复制分支',
                onTap: onFork!,
              ),
            if (tokens > 0 || responseMs != null)
              _MessageMeta(tokens: tokens, responseMs: responseMs),
          ],
        ),
      ],
    );
  }
}

class ModelSwitchNotice extends StatelessWidget {
  final String content;

  const ModelSwitchNotice({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swap_horiz_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentList extends StatelessWidget {
  final List<MessageAttachmentView> attachments;
  final AttachmentImageBuilder? imageBuilder;

  const _AttachmentList({required this.attachments, this.imageBuilder});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => _AttachmentChip(
              key: ValueKey(
                'message-attachment-${_attachmentIdentity(attachment)}',
              ),
              attachment: attachment,
              imageBuilder: imageBuilder,
            ),
          )
          .toList(),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final MessageAttachmentView attachment;
  final AttachmentImageBuilder? imageBuilder;

  const _AttachmentChip({
    super.key,
    required this.attachment,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (_canPreviewLocalImage(attachment)) {
      return _ImageAttachmentPreview(
        attachment: attachment,
        imageBuilder: imageBuilder,
      );
    }

    if (_canPreviewLocalVideo(attachment)) {
      return _VideoAttachmentPreview(attachment: attachment);
    }

    if (attachment.isAudio && attachment.hasLocalPath) {
      return _AudioAttachmentCard(attachment: attachment);
    }

    final scheme = Theme.of(context).colorScheme;
    final icon = switch (attachment.fileType) {
      'image' => Icons.image_outlined,
      'video' => Icons.movie_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'audio' => Icons.graphic_eq_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    final transcriptStatus = attachment.audioTranscriptStatus;
    final transcriptStatusColor = switch (transcriptStatus) {
      AudioTranscriptStatus.ready => scheme.primary,
      AudioTranscriptStatus.failed => scheme.error,
      AudioTranscriptStatus.empty => scheme.tertiary,
      _ => scheme.onSurfaceVariant,
    };
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurface),
                ),
                Text(
                  formatAttachmentSize(attachment.fileSize),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (attachment.isAudio && transcriptStatus != null)
                  Text(
                    '转写：${transcriptStatus.displayLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: transcriptStatusColor,
                      fontWeight:
                          transcriptStatus == AudioTranscriptStatus.failed
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                if (attachment.canOpenAudioTranscript)
                  Text(
                    '查看 / 复制转写稿',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (attachment.onDownload != null)
            IconButton(
              key: ValueKey(
                'download-attachment-${_attachmentIdentity(attachment)}',
              ),
              tooltip: '下载附件',
              style: _attachmentIconButtonStyle,
              onPressed: attachment.onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
            ),
        ],
      ),
    );
    final onCardTap = attachment.canOpenAudioTranscript
        ? attachment.onOpenAudioTranscript
        : attachment.onDownload;
    final child = onCardTap != null
        ? InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onCardTap,
            child: card,
          )
        : card;
    return Semantics(
      button: onCardTap != null,
      label:
          '附件 ${attachment.fileName} ${formatAttachmentSize(attachment.fileSize)}'
          '${transcriptStatus == null ? '' : ' 转写状态 ${transcriptStatus.displayLabel}'}'
          '${attachment.canOpenAudioTranscript
              ? ' 可查看和复制转写稿'
              : onCardTap == null
              ? ''
              : ' 可下载'}',
      child: child,
    );
  }
}

bool _canPreviewLocalImage(MessageAttachmentView attachment) {
  if (!attachment.isImage || !attachment.hasLocalPath) return false;
  try {
    return File(attachment.localPath!).existsSync();
  } catch (_) {
    return false;
  }
}

String _attachmentIdentity(MessageAttachmentView attachment) {
  final id = attachment.attachmentId?.trim();
  if (id != null && id.isNotEmpty) return id;
  // 文件名是旧构造方已有的稳定 identity；视频 controller 另在
  // didUpdateWidget 中比较 localPath，因此路径变化无需把所有测试 / UI key
  // 绑定到设备绝对路径。
  return attachment.fileName;
}

final ButtonStyle _attachmentIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size.square(44),
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
);

bool _canPreviewLocalVideo(MessageAttachmentView attachment) {
  if (kIsWeb || !attachment.isVideo || !attachment.hasLocalPath) return false;
  try {
    return File(attachment.localPath!).existsSync();
  } catch (_) {
    return false;
  }
}

class _AudioAttachmentCard extends StatelessWidget {
  final MessageAttachmentView attachment;

  const _AudioAttachmentCard({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = attachment.audioTranscriptStatus;
    final statusColor = switch (status) {
      AudioTranscriptStatus.ready => scheme.primary,
      AudioTranscriptStatus.failed => scheme.error,
      AudioTranscriptStatus.empty => scheme.tertiary,
      _ => scheme.onSurfaceVariant,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wrap 在窄屏消息气泡中会把可用宽度压到 200px 左右；显式服从
        // 这个约束，避免固定内容宽度把音频卡片推出屏幕。
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth < 320
            ? constraints.maxWidth
            : 320.0;
        final card = Container(
          key: ValueKey('audio-attachment-${_attachmentIdentity(attachment)}'),
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    ),
                    Text(
                      formatAttachmentSize(attachment.fileSize),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (status != null)
                      Text(
                        '转写：${status.displayLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                  ],
                ),
              ),
              if (attachment.onPlayAudio != null)
                IconButton(
                  key: ValueKey(
                    attachment.isPlayingAudio
                        ? 'stop-audio-${_attachmentIdentity(attachment)}'
                        : 'play-audio-${_attachmentIdentity(attachment)}',
                  ),
                  tooltip: attachment.isPlayingAudio ? '停止播放' : '播放音频',
                  style: _attachmentIconButtonStyle,
                  onPressed: attachment.onPlayAudio,
                  icon: Icon(
                    attachment.isPlayingAudio
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                ),
              if (attachment.onDownload != null)
                IconButton(
                  key: ValueKey(
                    'download-attachment-${_attachmentIdentity(attachment)}',
                  ),
                  tooltip: '下载附件',
                  style: _attachmentIconButtonStyle,
                  onPressed: attachment.onDownload,
                  icon: const Icon(Icons.download_outlined),
                ),
            ],
          ),
        );
        final child = attachment.canOpenAudioTranscript
            ? InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: attachment.onOpenAudioTranscript,
                child: card,
              )
            : card;
        return Semantics(
          button:
              attachment.canOpenAudioTranscript ||
              attachment.onPlayAudio != null ||
              attachment.onDownload != null,
          label:
              '音频附件 ${attachment.fileName} ${formatAttachmentSize(attachment.fileSize)}'
              '${attachment.onDownload == null ? '' : ' 可下载'}',
          child: child,
        );
      },
    );
  }
}

class _VideoAttachmentPreview extends StatefulWidget {
  final MessageAttachmentView attachment;

  const _VideoAttachmentPreview({required this.attachment});

  @override
  State<_VideoAttachmentPreview> createState() =>
      _VideoAttachmentPreviewState();
}

class _VideoAttachmentPreviewState extends State<_VideoAttachmentPreview> {
  VideoPlayerController? _controller;
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _createController();
    _controller?.addListener(_onControllerChanged);
  }

  void _createController() {
    try {
      final controller = VideoPlayerController.file(
        File(widget.attachment.localPath!),
      );
      _controller = controller;
      _initialization = controller.initialize();
    } catch (error, stackTrace) {
      // Stale or unsupported local media must degrade to a file card instead
      // of taking down the entire message list.
      _controller = null;
      _initialization = Future<void>.error(error, stackTrace);
    }
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _controller = null;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.attachment.localPath;
    final newPath = widget.attachment.localPath;
    final oldId = _attachmentIdentity(oldWidget.attachment);
    final newId = _attachmentIdentity(widget.attachment);
    if (oldPath == newPath && oldId == newId) return;
    _disposeController();
    _createController();
    _controller?.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // MessageBubble 的外层 padding 在小屏上会把可用宽度压到 280px
        // 甚至更小；固定 320px 会让视频卡片越过气泡边界并产生横向溢出。
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth < 320
            ? constraints.maxWidth
            : 320.0;
        return Container(
          key: ValueKey(
            'video-attachment-${_attachmentIdentity(widget.attachment)}',
          ),
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: FutureBuilder<void>(
            future: _initialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final controller = _controller;
              if (snapshot.hasError ||
                  controller == null ||
                  !controller.value.isInitialized) {
                return _VideoFallback(attachment: widget.attachment);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(controller),
                        IconButton.filledTonal(
                          tooltip: controller.value.isPlaying ? '暂停' : '播放',
                          onPressed: () {
                            if (controller.value.isPlaying) {
                              controller.pause();
                              return;
                            }
                            final duration = controller.value.duration;
                            if (duration > Duration.zero &&
                                controller.value.position >= duration) {
                              controller.seekTo(Duration.zero);
                            }
                            controller.play();
                          },
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                      ],
                    ),
                  ),
                  VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: VideoProgressColors(
                      playedColor: scheme.primary,
                      bufferedColor: scheme.primary.withValues(alpha: 0.3),
                      backgroundColor: scheme.outlineVariant,
                    ),
                  ),
                  _VideoFileCaption(attachment: widget.attachment),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _VideoFallback extends StatelessWidget {
  final MessageAttachmentView attachment;

  const _VideoFallback({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_outlined, size: 32, color: scheme.primary),
          const SizedBox(height: 8),
          _VideoFileCaption(attachment: attachment),
        ],
      ),
    );
  }
}

class _VideoFileCaption extends StatelessWidget {
  final MessageAttachmentView attachment;

  const _VideoFileCaption({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.movie_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${attachment.fileName} · ${formatAttachmentSize(attachment.fileSize)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
          if (attachment.onDownload != null)
            IconButton(
              key: ValueKey(
                'download-attachment-${_attachmentIdentity(attachment)}',
              ),
              tooltip: '下载附件',
              style: _attachmentIconButtonStyle,
              onPressed: attachment.onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
            ),
        ],
      ),
    );
  }
}

class _ImageAttachmentPreview extends StatelessWidget {
  final MessageAttachmentView attachment;
  final AttachmentImageBuilder? imageBuilder;

  const _ImageAttachmentPreview({required this.attachment, this.imageBuilder});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = File(attachment.localPath!);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与视频卡片一样，图片卡片必须服从气泡在手机上的剩余宽度；
        // 否则窄屏 + 用户消息内边距会出现横向溢出。
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth < 220
            ? constraints.maxWidth
            : 220.0;
        final preview = Semantics(
          label:
              '图片附件 ${attachment.fileName} ${formatAttachmentSize(attachment.fileSize)}',
          child: Container(
            key: ValueKey(
              'attachment-thumbnail-${_attachmentIdentity(attachment)}',
            ),
            width: width,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child:
                      imageBuilder?.call(context, attachment) ??
                      Image.file(
                        file,
                        fit: BoxFit.cover,
                        cacheWidth: 440,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                        errorBuilder: (context, error, stackTrace) {
                          return ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface,
                              ),
                            ),
                            Text(
                              formatAttachmentSize(attachment.fileSize),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (attachment.onDownload != null)
                        IconButton(
                          key: ValueKey(
                            'download-attachment-${_attachmentIdentity(attachment)}',
                          ),
                          tooltip: '下载附件',
                          visualDensity: VisualDensity.compact,
                          onPressed: attachment.onDownload,
                          icon: const Icon(Icons.download_outlined, size: 18),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (!attachment.canEditImage && attachment.onOpenImage == null) {
          return preview;
        }
        // 图片点击查看大图，长按进入编辑对话框。
        return GestureDetector(
          key: const ValueKey('edit-image-longpress'),
          onTap: attachment.onOpenImage,
          onLongPress: attachment.onEditImage,
          child: preview,
        );
      },
    );
  }
}

class _ThinkingBlock extends StatefulWidget {
  final String content;
  const _ThinkingBlock({required this.content});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        color: onTap == null
            ? Theme.of(context).disabledColor
            : Theme.of(context).colorScheme.onSurfaceVariant,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final int tokens;
  final int? responseMs;

  const _MessageMeta({required this.tokens, this.responseMs});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (tokens > 0) parts.add('$tokens tokens');
    if (responseMs != null) {
      parts.add(
        responseMs! >= 1000
            ? '${(responseMs! / 1000).toStringAsFixed(1)}s'
            : '${responseMs!}ms',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        parts.join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
