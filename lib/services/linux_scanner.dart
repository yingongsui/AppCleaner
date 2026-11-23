import 'dart:io';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/io_file_utils.dart';
import '../utils/platform_parsers.dart';
import 'linux_dependency_analyzer.dart';

/// Scans Linux installed applications (.desktop entries, dpkg/apt, pacman, dnf, flatpak, snap),
/// distinguishes User Installed Apps vs System Apps, locates XDG/Flatpak/Snap app data & cache,
/// and discovers orphaned leftovers.
class LinuxAppScanner {
  final LinuxDependencyAnalyzer dependencyAnalyzer;

  LinuxAppScanner({LinuxDependencyAnalyzer? dependencyAnalyzer})
      : dependencyAnalyzer = dependencyAnalyzer ?? LinuxDependencyAnalyzer();

  String get _homeDir => Platform.environment['HOME'] ?? '/home';
  String get _xdgConfigHome =>
      Platform.environment['XDG_CONFIG_HOME'] ?? '$_homeDir/.config';
  String get _xdgDataHome =>
      Platform.environment['XDG_DATA_HOME'] ?? '$_homeDir/.local/share';
  String get _xdgStateHome =>
      Platform.environment['XDG_STATE_HOME'] ?? '$_homeDir/.local/state';
  String get _xdgCacheHome =>
      Platform.environment['XDG_CACHE_HOME'] ?? '$_homeDir/.cache';

  static const Set<String> _coreSystemPackages = {
    'systemd',
    'gnome-control-center',
    'gnome-session-bin',
    'gnome-shell',
    'gnome-terminal',
    'nautilus',
    'dolphin',
    'konsole',
    'systemsettings',
    'nm-connection-editor',
    'network-manager-gnome',
    'policykit-1-gnome',
    'xdg-utils',
    'gcr',
    'ibus',
    'fcitx5',
    'im-config',
    'software-properties-gtk',
    'update-manager',
    'ubuntu-drivers-common',
    'malcontent-gui',
    'yelp',
  };

  static const Set<String> _ignoredLinuxOrphanFolders = {
    'gtk-2.0',
    'gtk-3.0',
    'gtk-4.0',
    'dconf',
    'pulse',
    'systemd',
    'ibus',
    'fcitx',
    'fcitx5',
    'fontconfig',
    'menus',
    'mime',
    'icons',
    'themes',
    'applications',
    'desktop-directories',
    'keyrings',
    'gvfs-metadata',
    'tracker',
    'tracker3',
    'evolution',
    'gnome-session',
    'gnome-shell',
    'gnome-control-center',
    'nautilus',
    'KDE',
    'kded5',
    'plasma',
    'autostart',
    'user-dirs.dirs',
    'user-dirs.locale',
    'pip',
    'npm',
    'yarn',
    'cargo',
    'rustup',
    'flutter',
    'dart',
    'mesa_shader_cache',
    'gstreamer-1.0',
    'thumbnails',
  };

  /// Scans all installed applications on Linux.
  Future<List<InstalledApp>> scanInstalledApps() async {
    final desktopDirs = <({
      String path,
      bool isUserDir,
      InstallSource defaultSource,
    })>[
      (
        path: '$_xdgDataHome/applications',
        isUserDir: true,
        defaultSource: InstallSource.appImageOrOpt,
      ),
      (
        path: '$_xdgDataHome/flatpak/exports/share/applications',
        isUserDir: true,
        defaultSource: InstallSource.flatpak,
      ),
      (
        path: '/var/lib/flatpak/exports/share/applications',
        isUserDir: true,
        defaultSource: InstallSource.flatpak,
      ),
      (
        path: '/var/lib/snapd/desktop/applications',
        isUserDir: true,
        defaultSource: InstallSource.snap,
      ),
      (
        path: '/usr/local/share/applications',
        isUserDir: true,
        defaultSource: InstallSource.appImageOrOpt,
      ),
      (
        path: '/usr/share/applications',
        isUserDir: false,
        defaultSource: InstallSource.aptDpkg,
      ),
    ];

    final manualPackages = await _fetchExplicitlyInstalledPackages();
    final runningProcesses = await _fetchRunningProcesses();
    final defaultPkgSource = await _detectPrimaryDistroSource();

    final seenDesktopIds = <String>{};
    final apps = <InstalledApp>[];

    for (final dirEntry in desktopDirs) {
      final dir = Directory(dirEntry.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> files = [];
      try {
        files = await dir.list(followLinks: true).toList();
      } catch (_) {
        continue;
      }

      for (final entity in files) {
        if (entity is! File || !entity.path.endsWith('.desktop')) continue;
        final desktopFileName = FormatUtils.basename(entity.path);
        final desktopId = desktopFileName.substring(
          0,
          desktopFileName.length - '.desktop'.length,
        );

        if (!seenDesktopIds.add(desktopId)) continue;

        final app = await _parseDesktopEntry(
          file: entity,
          desktopId: desktopId,
          isUserDir: dirEntry.isUserDir,
          defaultSource: dirEntry.defaultSource == InstallSource.aptDpkg
              ? defaultPkgSource
              : dirEntry.defaultSource,
          manualPackages: manualPackages,
          runningProcesses: runningProcesses,
        );
        if (app != null) {
          apps.add(app);
        }
      }
    }

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  Future<InstalledApp?> _parseDesktopEntry({
    required File file,
    required String desktopId,
    required bool isUserDir,
    required InstallSource defaultSource,
    required Set<String> manualPackages,
    required String runningProcesses,
  }) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      return null;
    }

    final fields = PlatformParsers.parseDesktopEntry(content);
    if (fields['NoDisplay']?.toLowerCase() == 'true' ||
        fields['Hidden']?.toLowerCase() == 'true') {
      return null;
    }

    final name = fields['Name'] ?? desktopId;
    final rawExec = fields['Exec'] ?? '';
    if (rawExec.isEmpty) return null;

    final execBinary = _extractBinaryFromExec(rawExec);
    final categories = fields['Categories'] ?? '';
    final flatpakId = fields['X-Flatpak'] ?? '';
    final snapName = fields['X-SnapInstanceName'] ?? '';

    InstallSource source = defaultSource;
    String? packageName;
    String identifier = desktopId;

    if (flatpakId.isNotEmpty || source == InstallSource.flatpak) {
      source = InstallSource.flatpak;
      identifier = flatpakId.isNotEmpty ? flatpakId : desktopId;
      packageName = identifier;
    } else if (snapName.isNotEmpty || source == InstallSource.snap) {
      source = InstallSource.snap;
      packageName = snapName.isNotEmpty ? snapName : desktopId.split('_').first;
      identifier = packageName;
    } else {
      final resolved = await dependencyAnalyzer.resolveOwningPackage(
        executablePath: execBinary,
        installPath: file.path,
        currentSource: source,
      );
      if (resolved.packageName != null) {
        packageName = resolved.packageName;
        identifier = packageName!;
      }
      if (resolved.source != null) {
        source = resolved.source!;
      }
    }

    final isSystemCategory = (categories.contains('System;') ||
            categories.contains('Core;') ||
            categories.contains('Settings;')) &&
        !categories.contains('Development;') &&
        !categories.contains('AudioVideo;') &&
        !categories.contains('Network;') &&
        !categories.contains('Office;') &&
        !categories.contains('Game;') &&
        !categories.contains('Graphics;');

    bool isSystemApp = false;
    if (!isUserDir &&
        source != InstallSource.flatpak &&
        source != InstallSource.snap) {
      if (packageName != null && _coreSystemPackages.contains(packageName)) {
        isSystemApp = true;
      } else if (isSystemCategory &&
          (packageName == null || !manualPackages.contains(packageName))) {
        isSystemApp = true;
      } else if (execBinary.startsWith('/usr/libexec/')) {
        isSystemApp = true;
      }
    }

    int appSize = 0;
    String version = fields['X-AppImage-Version'] ?? '';
    if (packageName != null &&
        (source == InstallSource.aptDpkg ||
            source == InstallSource.pacman ||
            source == InstallSource.dnfRpm)) {
      final meta = await _queryPackageVersionAndSize(packageName, source);
      if (meta.version.isNotEmpty) version = meta.version;
      if (meta.sizeBytes > 0) appSize = meta.sizeBytes;
    }

    final binBase = FormatUtils.basename(execBinary);
    final isRunning =
        binBase.length >= 3 && runningProcesses.contains(binBase);

    return InstalledApp(
      id: '${source.name}:$identifier:${file.path}',
      name: name,
      identifier: identifier,
      version: version,
      publisher: packageName ?? source.label,
      installPath: file.path,
      executablePath: execBinary,
      origin:
          isSystemApp ? AppOriginType.systemApp : AppOriginType.userInstalled,
      installSource: source,
      platform: DesktopPlatformType.linux,
      appSizeBytes: appSize,
      linuxPackageName: packageName,
      isRunning: isRunning,
    );
  }

  String _extractBinaryFromExec(String rawExec) {
    final cleaned = rawExec
        .replaceAll(RegExp(r'%[fFuUdDnNickvm]'), '')
        .replaceAll('"', '')
        .trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.first == 'env' && parts.length > 1) {
      for (final p in parts.skip(1)) {
        if (!p.contains('=')) return p;
      }
    }
    return parts.first;
  }

  /// Scans all data, config, cache, Flatpak/Snap sandbox data, and autostart items for [app].
  Future<List<AppDataItem>> scanAppDataItems(InstalledApp app) async {
    final items = <AppDataItem>[];
    final seenPaths = <String>{};

    final tokens = <String>{
      if (app.identifier.length >= 3) app.identifier,
      if (app.linuxPackageName != null && app.linuxPackageName!.length >= 3)
        app.linuxPackageName!,
      if (app.executablePath.isNotEmpty &&
          FormatUtils.basename(app.executablePath).length >= 3)
        FormatUtils.basename(app.executablePath),
      if (app.name.length >= 3) app.name,
    };
    final normalizedTokens = tokens
        .map(FormatUtils.normalizeToken)
        .where((t) => t.length >= 3)
        .toSet();

    // 1. Flatpak ~/.var/app/<appId>
    if (app.installSource == InstallSource.flatpak ||
        app.identifier.contains('.')) {
      final flatpakBase = '$_homeDir/.var/app/${app.identifier}';
      if (await Directory(flatpakBase).exists()) {
        final subDirs = <({
          String sub,
          DataCategory cat,
          String desc,
        })>[
          (
            sub: 'cache',
            cat: DataCategory.cache,
            desc: 'Flatpak sandbox cache (~/.var/app/.../cache)',
          ),
          (
            sub: 'config',
            cat: DataCategory.preferences,
            desc: 'Flatpak sandbox configuration (~/.var/app/.../config)',
          ),
          (
            sub: 'data',
            cat: DataCategory.appData,
            desc: 'Flatpak sandbox application data (~/.var/app/.../data)',
          ),
        ];
        for (final s in subDirs) {
          final p = '$flatpakBase/${s.sub}';
          if (await Directory(p).exists() && seenPaths.add(p)) {
            final size = await IoFileUtils.calculateEntitySize(p);
            items.add(
              AppDataItem(
                id: p,
                name: '${app.identifier}/${s.sub}',
                path: p,
                category: s.cat,
                sizeBytes: size,
                lastModified: await IoFileUtils.getLastModified(p),
                description: s.desc,
              ),
            );
          }
        }
      }
    }

    // 2. Snap ~/snap/<snapName>
    if (app.installSource == InstallSource.snap) {
      final snapName = app.linuxPackageName ?? app.identifier;
      final snapDir = '$_homeDir/snap/$snapName';
      if (await Directory(snapDir).exists() && seenPaths.add(snapDir)) {
        final size = await IoFileUtils.calculateEntitySize(snapDir);
        items.add(
          AppDataItem(
            id: snapDir,
            name: 'snap/$snapName',
            path: snapDir,
            category: DataCategory.container,
            sizeBytes: size,
            lastModified: await IoFileUtils.getLastModified(snapDir),
            description: 'Snap container user data & revisions (~/snap/$snapName)',
          ),
        );
      }
    }

    // 3. XDG Base Directories (~/.config, ~/.local/share, ~/.local/state, ~/.cache)
    final xdgTargets = <({
      String dir,
      DataCategory category,
      String description,
    })>[
      (
        dir: _xdgConfigHome,
        category: DataCategory.preferences,
        description: 'XDG user configuration & preferences (~/.config)',
      ),
      (
        dir: _xdgDataHome,
        category: DataCategory.appData,
        description: 'XDG persistent application data (~/.local/share)',
      ),
      (
        dir: _xdgStateHome,
        category: DataCategory.savedState,
        description: 'XDG application state & session history (~/.local/state)',
      ),
      (
        dir: _xdgCacheHome,
        category: DataCategory.cache,
        description: 'XDG runtime cache & thumbnails (~/.cache)',
      ),
    ];

    for (final target in xdgTargets) {
      final dir = Directory(target.dir);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        if (_ignoredLinuxOrphanFolders.contains(base)) continue;

        final normBase = FormatUtils.normalizeToken(base);
        final matched = tokens.any(
              (t) => base.toLowerCase() == t.toLowerCase(),
            ) ||
            (normBase.length >= 3 && normalizedTokens.contains(normBase));

        if (matched && seenPaths.add(entry.path)) {
          final size = await IoFileUtils.calculateEntitySize(entry.path);
          final stat = await FileStat.stat(entry.path);
          items.add(
            AppDataItem(
              id: entry.path,
              name: base,
              path: entry.path,
              category: target.category,
              sizeBytes: size,
              lastModified: stat.modified,
              isDirectory: stat.type == FileSystemEntityType.directory,
              description: target.description,
            ),
          );
        }
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  /// Scans XDG directories and Flatpak/Snap user folders for orphaned leftovers on Linux.
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) async {
    final installedNorms = <String>{};
    for (final app in installedApps) {
      for (final token in [
        app.identifier,
        app.name,
        app.linuxPackageName ?? '',
        FormatUtils.basename(app.executablePath),
      ]) {
        final norm = FormatUtils.normalizeToken(token);
        if (norm.length >= 2) installedNorms.add(norm);
      }
    }

    final scanTargets = <({String path, DataCategory category})>[
      (path: _xdgConfigHome, category: DataCategory.preferences),
      (path: _xdgCacheHome, category: DataCategory.cache),
      (path: _xdgDataHome, category: DataCategory.appData),
      (path: '$_homeDir/.var/app', category: DataCategory.container),
      (path: '$_homeDir/snap', category: DataCategory.container),
    ];

    final grouped = <String, List<AppDataItem>>{};
    final titles = <String, String>{};

    for (final target in scanTargets) {
      final dir = Directory(target.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        if (base.startsWith('.') ||
            _ignoredLinuxOrphanFolders.contains(base)) {
          continue;
        }
        final norm = FormatUtils.normalizeToken(base);
        if (norm.length < 3 || installedNorms.contains(norm)) continue;

        final size = await IoFileUtils.calculateEntitySize(
          entry.path,
          maxFiles: 1500,
        );
        if (size == 0) continue;

        final stat = await FileStat.stat(entry.path);
        titles.putIfAbsent(norm, () => base);
        grouped.putIfAbsent(norm, () => []).add(
              AppDataItem(
                id: entry.path,
                name: base,
                path: entry.path,
                category: target.category,
                sizeBytes: size,
                lastModified: stat.modified,
                isDirectory: stat.type == FileSystemEntityType.directory,
                description:
                    'Orphaned directory not matching any installed Linux package or .desktop entry',
              ),
            );
      }
    }

    final groups = <OrphanLeftoverGroup>[];
    grouped.forEach((key, list) {
      groups.add(
        OrphanLeftoverGroup(
          id: key,
          suspectedAppName: titles[key] ?? key,
          identifier: key,
          platform: DesktopPlatformType.linux,
          confidenceReason:
              'Corresponding DEB/RPM/Pacman/Flatpak package was uninstalled',
          items: list,
        ),
      );
    });
    groups.sort((a, b) => b.totalSizeBytes.compareTo(a.totalSizeBytes));
    return groups;
  }

  Future<Set<String>> _fetchExplicitlyInstalledPackages() async {
    final set = <String>{};
    try {
      final res = await Process.run('apt-mark', ['showmanual']);
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final p = line.trim().split(':').first;
          if (p.isNotEmpty) set.add(p);
        }
        return set;
      }
    } catch (_) {}

    try {
      final res = await Process.run('pacman', ['-Qeq']);
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final p = line.trim();
          if (p.isNotEmpty) set.add(p);
        }
      }
    } catch (_) {}
    return set;
  }

  Future<InstallSource> _detectPrimaryDistroSource() async {
    if (await File('/usr/bin/apt-get').exists()) return InstallSource.aptDpkg;
    if (await File('/usr/bin/pacman').exists()) return InstallSource.pacman;
    if (await File('/usr/bin/dnf').exists()) return InstallSource.dnfRpm;
    return InstallSource.aptDpkg;
  }

  Future<({String version, int sizeBytes})> _queryPackageVersionAndSize(
    String packageName,
    InstallSource source,
  ) async {
    try {
      if (source == InstallSource.aptDpkg) {
        final res = await Process.run('dpkg-query', [
          '-W',
          r'-f=${Version}\t${Installed-Size}',
          packageName,
        ]);
        if (res.exitCode == 0) {
          final parts = (res.stdout as String).trim().split('\t');
          final ver = parts.isNotEmpty ? parts[0] : '';
          final kb = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
          return (version: ver, sizeBytes: kb * 1024);
        }
      }
    } catch (_) {}
    return (version: '', sizeBytes: 0);
  }

  Future<String> _fetchRunningProcesses() async {
    try {
      final res = await Process.run('ps', ['-axo', 'comm']);
      if (res.exitCode == 0) return res.stdout as String;
    } catch (_) {}
    return '';
  }
}
