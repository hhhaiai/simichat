import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const kIosBackgroundDreamingSmokeResultDirectory =
    'ai_chat/ios_background_dreaming_smoke';
const kIosBackgroundDreamingSmokeResultFileName =
    'ios-background-dreaming-smoke.json';

Future<void> writeIosBackgroundDreamingSmokeResult(
  Map<String, Object?> data,
) async {
  final root = await getApplicationDocumentsDirectory();
  final directory = Directory(
    p.join(root.path, kIosBackgroundDreamingSmokeResultDirectory),
  );
  await directory.create(recursive: true);
  final file = File(
    p.join(directory.path, kIosBackgroundDreamingSmokeResultFileName),
  );
  await file.writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'updatedAt': DateTime.now().toIso8601String(), ...data}),
    flush: true,
  );
}
