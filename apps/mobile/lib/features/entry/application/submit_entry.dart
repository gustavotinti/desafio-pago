import 'package:image_picker/image_picker.dart';

import '../domain/entities/content_type.dart';
import '../infrastructure/entry_repository.dart';

class SubmitEntry {
  final EntryRepository _repository;

  SubmitEntry(this._repository);

  Future<String?> call({
    required String challengeId,
    required ContentType contentType,
    String? contentText,
    XFile? contentFile,
    String? videoUrl,
  }) =>
      _repository.submitEntry(
        challengeId: challengeId,
        contentType: contentType,
        contentText: contentText,
        contentFile: contentFile,
        videoUrl: videoUrl,
      );
}
