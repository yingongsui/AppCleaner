import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native macOS MethodChannel bridge to fetch crisp PNG icons for any `.app`
/// bundle (both User Apps and System Apps, including `Assets.car` icons)
/// via `NSWorkspace.shared.icon(forFile:)`.
class MacOsNativeIconBridge {
  static const MethodChannel _channel = MethodChannel('app_cleaner/native');

  /// Fetches a 128x128 PNG icon for [appPath] on macOS.
  /// Returns `null` if unavailable (e.g., on non-macOS platforms or in unit tests).
  static Future<Uint8List?> getAppIconPng(String appPath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return null;
    }
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'getAppIcon',
        {'path': appPath, 'size': 128},
      );
      return result;
    } catch (_) {
      return null;
    }
  }
}
