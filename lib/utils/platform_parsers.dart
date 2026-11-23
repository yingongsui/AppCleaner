import '../models/app_models.dart';

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
}
