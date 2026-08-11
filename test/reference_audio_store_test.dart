import 'dart:io';

import 'package:ai_chat_app/core/media/openai_text_to_speech_engine.dart';
import 'package:ai_chat_app/core/media/reference_audio_store.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('archives wav atomically and keeps it after source deletion', () async {
    final temp = await Directory.systemTemp.createTemp('simichat_ref_audio_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final support = Directory(p.join(temp.path, 'support'));
    final source = File(p.join(temp.path, '我的声音.wav'));
    const bytes = <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4];
    await source.writeAsBytes(bytes);
    final store = ReferenceAudioStore(
      rootResolver: () async => support,
      now: () => DateTime.fromMicrosecondsSinceEpoch(123456),
    );

    final archivedPath = await store.archiveWav(source.path);

    expect(archivedPath, isNot(source.path));
    expect(p.basename(archivedPath), '我的声音.wav');
    expect(
      p.isWithin(p.join(support.path, 'tts', 'reference_audio'), archivedPath),
      isTrue,
    );
    expect(await File(archivedPath).readAsBytes(), bytes);
    expect(
      support
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.part')),
      isEmpty,
    );

    await source.delete();
    expect(await File(archivedPath).readAsBytes(), bytes);
    expect(await store.archiveWav(archivedPath), archivedPath);
  });

  test(
    'rejects invalid reference files before creating a private copy',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'simichat_ref_audio_invalid_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final support = Directory(p.join(temp.path, 'support'));
      final store = ReferenceAudioStore(rootResolver: () async => support);
      final empty = File(p.join(temp.path, 'empty.wav'));
      await empty.create();
      final wrongType = File(p.join(temp.path, 'voice.mp3'));
      await wrongType.writeAsBytes([1]);
      final oversized = File(p.join(temp.path, 'large.wav'));
      await oversized.open(mode: FileMode.write).then((file) async {
        await file.truncate(kTextToSpeechMaxReferenceAudioBytes + 1);
        await file.close();
      });

      for (final (path, message) in [
        (empty.path, '为空'),
        (wrongType.path, '仅支持 WAV'),
        (oversized.path, '超过 10 MB'),
        (p.join(temp.path, 'missing.wav'), '不存在'),
      ]) {
        await expectLater(
          store.archiveWav(path),
          throwsA(
            isA<TextToSpeechException>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
      }
      expect(await support.exists(), isFalse);
    },
  );

  test('deleteManaged never deletes an external source file', () async {
    final temp = await Directory.systemTemp.createTemp(
      'simichat_ref_audio_delete_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final support = Directory(p.join(temp.path, 'support'));
    final source = File(p.join(temp.path, 'external.wav'));
    await source.writeAsBytes([1, 2, 3]);
    final store = ReferenceAudioStore(rootResolver: () async => support);

    await store.deleteManaged(source.path);

    expect(await source.exists(), isTrue);
  });

  test('concurrent archives use separate atomic staging directories', () async {
    final temp = await Directory.systemTemp.createTemp(
      'simichat_ref_audio_concurrent_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final support = Directory(p.join(temp.path, 'support'));
    final first = File(p.join(temp.path, 'first.wav'));
    final second = File(p.join(temp.path, 'second.wav'));
    await first.writeAsBytes([1, 2, 3]);
    await second.writeAsBytes([4, 5, 6]);
    final store = ReferenceAudioStore(
      rootResolver: () async => support,
      now: () => DateTime.fromMicrosecondsSinceEpoch(111),
    );

    final archived = await Future.wait([
      store.archiveWav(first.path),
      store.archiveWav(second.path),
    ]);

    expect(archived.toSet(), hasLength(2));
    expect(await File(archived[0]).readAsBytes(), [1, 2, 3]);
    expect(await File(archived[1]).readAsBytes(), [4, 5, 6]);
    expect(
      support
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.part')),
      isEmpty,
    );
  });
}
