import '../models/app_models.dart';

/// Pure Dart helper for Linux dependency command generation, APT history log parsing,
/// and cross-platform parsers (safe for both Desktop and Flutter Web).
class LinuxCommandHelper {
  /// Pure parser for `/var/log/apt/history.log` content.
  static Set<String> parseAptHistoryLogContent(
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

  /// Pure Dart XML Info.plist key-string extractor.
  static Map<String, String> parseXmlPlistString(String xml) {
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

  /// Parses standard freedesktop.org `.desktop` entry key-values under `[Desktop Entry]`.
  static Map<String, String> parseDesktopFileContent(String content) {
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

  /// Builds the exact shell command to uninstall the Linux package and selected dependencies.
  static List<String> buildUninstallCommand({
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
}
