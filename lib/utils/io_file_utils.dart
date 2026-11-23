import 'dart:io';

/// Desktop-only (`dart:io`) filesystem size and timestamp calculation utilities.
class IoFileUtils {
  /// Computes the size of a FileSystemEntity with depth and item limits for responsiveness.
  static Future<int> calculateEntitySize(
    String path, {
    int maxFiles = 6500,
  }) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return 0;
      if (type == FileSystemEntityType.file) {
        return await File(path).length();
      }
      if (type == FileSystemEntityType.directory) {
        int total = 0;
        int count = 0;
        final dir = Directory(path);
        await for (final entity
            in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
          if (entity is File) {
            try {
              total += await entity.length();
            } catch (_) {}
          }
          count++;
          if (count >= maxFiles) break;
        }
        return total;
      }
    } catch (_) {}
    return 0;
  }

  /// Gets the last modified timestamp of a file or directory.
  static Future<DateTime?> getLastModified(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) return null;
      return stat.modified;
    } catch (_) {
      return null;
    }
  }
}
