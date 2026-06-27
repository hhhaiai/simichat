import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcript_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio transcript details read benchmark', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'simichat_audio_transcript_details_benchmark_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final archive = AudioTranscriptArchive(rootDirectory: tempDir);
    const fileCount = 300;
    for (var i = 0; i < fileCount; i++) {
      await archive.writeDraft(
        messageId: 'message-$i',
        attachmentId: 'attachment-$i',
        fileName: 'voice-$i.m4a',
        fileSize: 2048,
        transcript: '第 $i 条转写正文\n第二行',
        createdAt: DateTime.utc(2026, 6, 27),
      );
    }

    final stopwatch = Stopwatch()..start();
    var copyable = 0;
    for (var i = 0; i < fileCount; i++) {
      final details = await archive.readDetails(
        messageId: 'message-$i',
        attachmentId: 'attachment-$i',
      );
      if (details?.hasCopyableTranscript == true) copyable++;
    }
    stopwatch.stop();

    // ignore: avoid_print
    print(
      'audio_transcript_details_benchmark files=$fileCount '
      'read_ms=${stopwatch.elapsedMilliseconds} copyable=$copyable',
    );
    expect(copyable, fileCount);
  });
}
