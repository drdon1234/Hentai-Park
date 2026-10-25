import '../core/models.dart';

/// Resolves only the chapter named by an update event; a stale ID must not open another chapter.
Chapter? findUpdateChapter(
  WorkDetail detail, {
  required String workId,
  required String chapterId,
}) {
  if (detail.id != workId || chapterId.isEmpty) return null;
  return detail.chapters
      ?.where((chapter) => chapter.id == chapterId)
      .firstOrNull;
}
