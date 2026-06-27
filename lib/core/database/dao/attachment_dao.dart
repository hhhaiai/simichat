import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'attachment_dao.g.dart';

@DriftAccessor(tables: [Attachments])
class AttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentDaoMixin {
  AttachmentDao(super.db);

  Future<List<Attachment>> getAttachmentsByMessage(String messageId) {
    return (select(
      attachments,
    )..where((t) => t.messageId.equals(messageId))).get();
  }

  Future<List<Attachment>> getAllAttachments() {
    return (select(attachments)..orderBy([
          (t) => OrderingTerm(expression: t.createdAt),
          (t) => OrderingTerm(expression: t.id),
        ]))
        .get();
  }

  Future<int> insertAttachment({
    required String id,
    required String messageId,
    required String fileType,
    required String localPath,
    required String fileName,
    required int fileSize,
  }) {
    return into(attachments).insert(
      AttachmentsCompanion.insert(
        id: id,
        messageId: messageId,
        fileType: fileType,
        localPath: localPath,
        fileName: fileName,
        fileSize: fileSize,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> deleteAttachment(String id) {
    return (delete(attachments)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteByMessage(String messageId) {
    return (delete(
      attachments,
    )..where((t) => t.messageId.equals(messageId))).go();
  }
}
