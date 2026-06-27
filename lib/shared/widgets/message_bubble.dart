import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/media/audio_transcript_archive.dart';
import 'latex_markdown_widget.dart';

const double _kChatContentMaxWidth = 860;

typedef AttachmentImageBuilder =
    Widget Function(BuildContext context, MessageAttachmentView attachment);

class MessageAttachmentView {
  final String fileName;
  final String fileType;
  final int fileSize;
  final String? localPath;
  final AudioTranscriptStatus? audioTranscriptStatus;
  final VoidCallback? onOpenAudioTranscript;

  const MessageAttachmentView({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    this.localPath,
    this.audioTranscriptStatus,
    this.onOpenAudioTranscript,
  });

  bool get isImage => fileType == 'image';

  bool get isAudio => fileType == 'audio';

  bool get hasLocalPath => localPath != null && localPath!.isNotEmpty;

  bool get canOpenAudioTranscript => isAudio && onOpenAudioTranscript != null;
}

/// ChatGPT-style message row: assistant answers are plain content blocks;
/// user messages are compact right-aligned bubbles.
class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final String? thinkingContent;
  final int tokens;
  final int? responseMs;
  final bool isUser;
  final VoidCallback? onRetry;
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
    required this.role,
    required this.content,
    this.thinkingContent,
    this.tokens = 0,
    this.responseMs,
    required this.isUser,
    this.onRetry,
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
                if (content.isNotEmpty)
                  SelectableText(
                    content,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
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
        LatexMarkdownWidget(data: content),
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
              onTap: onRetry ?? () {},
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

  const _AttachmentChip({required this.attachment, this.imageBuilder});

  @override
  Widget build(BuildContext context) {
    if (_canPreviewLocalImage(attachment)) {
      return _ImageAttachmentPreview(
        attachment: attachment,
        imageBuilder: imageBuilder,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final icon = switch (attachment.fileType) {
      'image' => Icons.image_outlined,
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
      button: attachment.canOpenAudioTranscript,
      label:
          '附件 ${attachment.fileName} ${formatAttachmentSize(attachment.fileSize)}'
          '${transcriptStatus == null ? '' : ' 转写状态 ${transcriptStatus.displayLabel}'}'
          '${attachment.canOpenAudioTranscript ? ' 可查看和复制转写稿' : ''}',
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

class _ImageAttachmentPreview extends StatelessWidget {
  final MessageAttachmentView attachment;
  final AttachmentImageBuilder? imageBuilder;

  const _ImageAttachmentPreview({required this.attachment, this.imageBuilder});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = File(attachment.localPath!);
    return Semantics(
      label:
          '图片附件 ${attachment.fileName} ${formatAttachmentSize(attachment.fileSize)}',
      child: Container(
        key: ValueKey('attachment-thumbnail-${attachment.fileName}'),
        width: 220,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 16, color: scheme.primary),
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
                ],
              ),
            ),
          ],
        ),
      ),
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
        visualDensity: VisualDensity.compact,
        color: onTap == null
            ? Theme.of(context).disabledColor
            : Theme.of(context).colorScheme.onSurfaceVariant,
        style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
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
