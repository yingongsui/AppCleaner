import '../models/app_models.dart';
import 'format_utils.dart';

/// Pure Dart cross-platform parsers, command builders, and safety validators
/// (safe for both Desktop and Flutter Web).
class PlatformParsers {
  /// Parses `/var/log/apt/history.log` to find companion packages installed
  /// automatically in the same transaction as [targetPackage].
  static Set<String> parseAptHistoryCompanions(
    String logContent,
    String targetPackage,
  ) {
    final companions = <String>{};
    final blocks = logContent.split(RegExp(r'\n\s*\n'));
    final pkgPattern = RegExp(
      r'([a-zA-Z0-9.+_-]+)(?::[a-z0-9]+)?\s*\(([^)]+)\)',
    );

    for (final block in blocks) {
      String? installLine;
      for (final line in block.split('\n')) {
        if (line.startsWith('Install:')) {
          installLine = line.substring('Install:'.length).trim();
          break;
        }
      }
      if (installLine == null) continue;

      final matches = pkgPattern.allMatches(installLine).toList();
      final namesInBlock = <String>{};
      final autoInBlock = <String>{};

      for (final m in matches) {
        final name = m.group(1)!.trim();
        final details = m.group(2) ?? '';
        namesInBlock.add(name);
        if (details.contains('automatic')) {
          autoInBlock.add(name);
        }
      }

      if (namesInBlock.contains(targetPackage)) {
        companions.addAll(autoInBlock);
        companions.remove(targetPackage);
      }
    }
    return companions;
  }

  /// Extracts top-level `<key>` / `<string>` pairs from a macOS XML `Info.plist`.
  static Map<String, String> parseXmlPlist(String xml) {
    final result = <String, String>{};
    final reg = RegExp(
      r'<key>\s*([^<]+?)\s*</key>\s*<string>\s*([^<]*?)\s*</string>',
      multiLine: true,
    );
    for (final m in reg.allMatches(xml)) {
      final k = m.group(1)?.trim() ?? '';
      final v = m.group(2)?.trim() ?? '';
      if (k.isNotEmpty) {
        result[k] = v;
      }
    }
    return result;
  }

  /// Parses standard freedesktop.org `.desktop` key-value pairs under `[Desktop Entry]`.
  static Map<String, String> parseDesktopEntry(String content) {
    final map = <String, String>{};
    bool inDesktopEntry = false;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        if (line == '[Desktop Entry]') {
          inDesktopEntry = true;
        } else if (inDesktopEntry) {
          break;
        }
        continue;
      }
      if (!inDesktopEntry) continue;
      final eq = line.indexOf('=');
      if (eq > 0) {
        final key = line.substring(0, eq).trim();
        final value = line.substring(eq + 1).trim();
        map.putIfAbsent(key, () => value);
      }
    }
    return map;
  }

  /// Builds the exact shell command to uninstall a Linux package and selected dependencies.
  static List<String> buildLinuxUninstallCommand({
    required InstalledApp app,
    required List<LinuxDependencyPackage> selectedDependencies,
    bool usePkexec = true,
  }) {
    final pkg = app.linuxPackageName ?? app.identifier;
    final extraPkgs = selectedDependencies
        .map((d) => d.packageName)
        .where((p) => p.isNotEmpty && p != pkg)
        .toList();

    switch (app.installSource) {
      case InstallSource.flatpak:
        return [
          'flatpak',
          'uninstall',
          '-y',
          '--delete-data',
          app.identifier,
        ];
      case InstallSource.snap:
        return [
          if (usePkexec) 'pkexec',
          'snap',
          'remove',
          '--purge',
          pkg,
        ];
      case InstallSource.pacman:
        return [
          if (usePkexec) 'pkexec',
          'pacman',
          '-Rns',
          '--noconfirm',
          pkg,
          ...extraPkgs,
        ];
      case InstallSource.dnfRpm:
        return [
          if (usePkexec) 'pkexec',
          'dnf',
          'remove',
          '-y',
          pkg,
          ...extraPkgs,
        ];
      case InstallSource.aptDpkg:
      default:
        return [
          if (usePkexec) 'pkexec',
          'apt-get',
          'purge',
          '-y',
          '--auto-remove',
          pkg,
          ...extraPkgs,
        ];
    }
  }

  /// Safety guard ensuring critical Windows root Registry hives can never be deleted.
  static bool isSafeWindowsRegistryKeyPath(String keyPath) {
    final normalized = keyPath.trim().replaceAll('/', r'\').toUpperCase();
    final parts = normalized.split(r'\').where((p) => p.isNotEmpty).toList();
    if (parts.length < 3) return false;

    const protectedPrefixes = {
      r'HKCU\SOFTWARE\MICROSOFT\WINDOWS',
      r'HKLM\SOFTWARE\MICROSOFT\WINDOWS',
      r'HKLM\SYSTEM',
      r'HKLM\SECURITY',
      r'HKLM\SAM',
      r'HKCU\SOFTWARE\CLASSES',
      r'HKLM\SOFTWARE\CLASSES',
    };

    // Allow specific application Uninstall subkeys (depth >= 6), block parent system keys.
    if (normalized.contains(r'\CURRENTVERSION\UNINSTALL\') &&
        parts.length >= 6) {
      return true;
    }

    for (final protected in protectedPrefixes) {
      if (normalized == protected || normalized.startsWith('$protected\\')) {
        return false;
      }
    }

    // Block deleting top-level WOW6432Node or Microsoft vendor node directly.
    if (normalized == r'HKLM\SOFTWARE\WOW6432NODE' ||
        normalized == r'HKCU\SOFTWARE\MICROSOFT' ||
        normalized == r'HKLM\SOFTWARE\MICROSOFT') {
      return false;
    }

    return true;
  }

  /// Strips trailing version numbers, release channels, and common config
  /// extensions so folder/config names like `LyX-2.4`, `lyx2.4`, `GIMP-2.10`,
  /// `python3.12`, or `discord-canary` resolve to their base app name (`LyX`,
  /// `GIMP`, `python`, `discord`).
  static String stripVersionAndChannelSuffix(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    const extensions = [
      '.savedstate',
      '.binarycookies',
      '.plist',
      '.conf',
      '.cfg',
      '.ini',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.toml',
      '.db',
      '.sqlite',
      '.log',
      '.cache',
      '.app',
      '.desktop',
    ];
    final lowerInit = s.toLowerCase();
    for (final ext in extensions) {
      if (lowerInit.endsWith(ext) && s.length > ext.length) {
        s = s.substring(0, s.length - ext.length);
        break;
      }
    }

    final sepVersionReg = RegExp(
      r'[-_.\s]+v?\d+(?:\.\d+)*(?:[-_.]?(?:alpha|beta|rc\d*|dev|nightly|canary|esr|lts|insiders|preview|snapshot))?$',
      caseSensitive: false,
    );
    final attachedVersionReg = RegExp(
      r'(?<=[a-zA-Z])v?\d+(?:\.\d+)+$',
      caseSensitive: false,
    );
    final channelOrRoleReg = RegExp(
      r'[-_.\s]+(?:canary|beta|alpha|dev|nightly|esr|insiders|preview|lts|stable|qt5|qt6|gtk2|gtk3|gtk4|bin|data|cache|config|settings|profile|profiles|logs|helper|updater|crashpad|cef|webview|runtime|common|desktop|client|cli|gui)$',
      caseSensitive: false,
    );
    final trailingMajorDigitReg =
        RegExp(r'^([a-zA-Z][a-zA-Z0-9_-]{2,}?)\d{1,2}$');

    for (var i = 0; i < 3; i++) {
      final before = s;
      s = s.replaceFirst(sepVersionReg, '').trim();
      s = s.replaceFirst(attachedVersionReg, '').trim();
      s = s.replaceFirst(channelOrRoleReg, '').trim();
      if (s == before) break;
    }

    // Peel a trailing major version digit on 3+ letter names (e.g. python3 -> python, godot4 -> godot)
    final digitMatch = trailingMajorDigitReg.firstMatch(s);
    if (digitMatch != null) {
      final candidate = digitMatch.group(1)!;
      if (candidate.replaceAll(RegExp(r'[^a-zA-Z]'), '').length >= 3) {
        s = candidate;
      }
    }

    return s.trim();
  }

  /// Adds both raw normalized and version-stripped normalized tokens from [raw]
  /// into [target] for accurate cross-referencing against installed apps/packages.
  static void addNormalizedAppTokens(Set<String> target, String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final rawNorm = FormatUtils.normalizeToken(trimmed);
    if (rawNorm.length >= 2) {
      target.add(rawNorm);
    }

    final stripped = stripVersionAndChannelSuffix(trimmed);
    final strippedNorm = FormatUtils.normalizeToken(stripped);
    if (strippedNorm.length >= 2) {
      target.add(strippedNorm);
    }

    if (stripped.contains('.')) {
      final parts = stripped.split('.').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        final last = parts.last;
        final lastNorm = FormatUtils.normalizeToken(last);
        if (lastNorm.length >= 3) target.add(lastNorm);
        final lastStrippedNorm =
            FormatUtils.normalizeToken(stripVersionAndChannelSuffix(last));
        if (lastStrippedNorm.length >= 3) target.add(lastStrippedNorm);
      }
    }
  }

  /// Returns `true` if a candidate config/cache directory name (such as
  /// `LyX-2.4`, `lyx2.4`, `GIMP-2.10`, `org.lyx.LyX`, or `discord-canary`)
  /// matches any currently installed application, package, or CLI binary token.
  static bool matchesInstalledIdentifier(
    String candidateRaw,
    Set<String> installedNormalizedTokens,
  ) {
    final trimmed = candidateRaw.trim();
    if (trimmed.isEmpty) return true;

    final rawNorm = FormatUtils.normalizeToken(trimmed);
    if (rawNorm.length < 2) return true;
    if (installedNormalizedTokens.contains(rawNorm)) return true;

    final stripped = stripVersionAndChannelSuffix(trimmed);
    final strippedNorm = FormatUtils.normalizeToken(stripped);
    if (strippedNorm.length >= 2 &&
        installedNormalizedTokens.contains(strippedNorm)) {
      return true;
    }

    // Check reverse-DNS segments on the version-stripped string first so
    // `org.lyx.LyX-2.4` -> `org.lyx.LyX` -> trailing segment `LyX` -> `lyx`.
    for (final candidate in {stripped, trimmed}) {
      if (candidate.contains('.')) {
        final parts = candidate.split('.').where((p) => p.isNotEmpty).toList();
        if (parts.length >= 2) {
          final last = parts.last;
          final lastNorm = FormatUtils.normalizeToken(last);
          if (lastNorm.length >= 3 &&
              installedNormalizedTokens.contains(lastNorm)) {
            return true;
          }
          final lastStripped =
              FormatUtils.normalizeToken(stripVersionAndChannelSuffix(last));
          if (lastStripped.length >= 3 &&
              installedNormalizedTokens.contains(lastStripped)) {
            return true;
          }
        }
      }
    }

    final segments = trimmed
        .split(RegExp(r'[-_\s]+'))
        .where((seg) => seg.isNotEmpty)
        .toList();
    if (segments.length >= 2) {
      final first = FormatUtils.normalizeToken(segments.first);
      final second = segments[1];
      final secondLooksLikeVersionOrVariant =
          RegExp(r'^v?\d').hasMatch(second) ||
              const {
                'config',
                'cache',
                'data',
                'settings',
                'user',
                'profile',
                'profiles',
                'beta',
                'canary',
                'dev',
                'nightly',
                'esr',
                'lts',
                'insiders',
                'preview',
                'helper',
                'updater',
                'common',
                'desktop',
                'client',
                'qt5',
                'qt6',
                'gtk2',
                'gtk3',
                'gtk4',
              }.contains(second.toLowerCase());
      if (secondLooksLikeVersionOrVariant &&
          first.length >= 3 &&
          installedNormalizedTokens.contains(first)) {
        return true;
      }
    }

    return false;
  }
}
