import 'dart:io';

import 'format_utils.dart';

/// Desktop-only (`dart:io`) filesystem size, timestamp, self-protection, and
/// persistent history path utilities.
class IoFileUtils {
  /// Computes the size of a FileSystemEntity.
  /// Uses native `du -sk` on macOS/Linux for fast, exact directory sizing without
  /// file-count truncation, falling back to Dart directory traversal on Windows or error.
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
        if (Platform.isMacOS || Platform.isLinux) {
          try {
            final res = await Process.run('du', ['-sk', path]);
            if (res.exitCode == 0) {
              final token =
                  (res.stdout as String).trim().split(RegExp(r'\s+')).first;
              final kb = int.tryParse(token);
              if (kb != null) return kb * 1024;
            }
          } catch (_) {}
        }

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

  /// Determines whether the inspected app entry is AppCleaner itself (self-lock guard).
  static bool isSelfApplication({
    required String installPath,
    required String identifier,
    required String name,
    String executablePath = '',
  }) {
    final normId = identifier.toLowerCase().trim();
    if (normId == 'com.yin.appcleaner' ||
        normId == 'com.example.appcleaner' ||
        normId == 'com.example.app_cleaner' ||
        normId == 'appcleaner' ||
        normId == 'app-cleaner' ||
        normId == 'app_cleaner') {
      return true;
    }

    final normName = FormatUtils.normalizeToken(name);
    if (normName == 'appcleaner') {
      return true;
    }

    try {
      final currentExe =
          Platform.resolvedExecutable.toLowerCase().replaceAll(r'\', '/');
      final normInstall = installPath.toLowerCase().replaceAll(r'\', '/');
      if (normInstall.isNotEmpty &&
          (currentExe == normInstall ||
              currentExe.startsWith('$normInstall/'))) {
        return true;
      }
      final normExe = executablePath.toLowerCase().replaceAll(r'\', '/');
      if (normExe.isNotEmpty && currentExe == normExe) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Returns the platform-appropriate JSON file path for persisting operation history.
  static String getHistoryFilePath() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/Users/Shared';
      return '$home/Library/Application Support/AppCleaner/history.json';
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/home';
      final xdgData =
          Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
      return '$xdgData/AppCleaner/history.json';
    }
    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ?? r'C:\Users\Default\AppData\Roaming';
      return '$appData\\AppCleaner\\history.json';
    }
    return 'app_cleaner_history.json';
  }
}
