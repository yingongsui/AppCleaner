import 'package:flutter/foundation.dart';

/// Pure Dart formatting and path helpers safe for both Desktop and Web.
class FormatUtils {
  /// Formats a byte count into human-readable string (B, KB, MB, GB).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) return '${size.toInt()} B';
    return '${size.toStringAsFixed(size >= 100 ? 0 : (size >= 10 ? 1 : 2))} ${units[unitIndex]}';
  }

  /// Formats a DateTime into YYYY-MM-DD HH:mm.
  static String formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  /// Normalizes an application or bundle token for matching directories.
  static String normalizeToken(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .trim();
  }

  /// Joins path segments using the active platform's path separator.
  static String joinPath(List<String> parts) {
    final sep = defaultTargetPlatform == TargetPlatform.windows ? r'\' : '/';
    final cleaned = <String>[];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (p.isEmpty) continue;
      if (i > 0) {
        while (p.startsWith('/') || p.startsWith(r'\')) {
          p = p.substring(1);
        }
      }
      if (i < parts.length - 1) {
        while (p.endsWith('/') || p.endsWith(r'\')) {
          p = p.substring(0, p.length - 1);
        }
      }
      if (p.isNotEmpty) cleaned.add(p);
    }
    return cleaned.join(sep);
  }

  /// Gets the base name of a file or directory path.
  static String basename(String path) {
    var normalized = path.replaceAll(r'\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }
}
