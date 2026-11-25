import 'dart:io';
import 'dart:typed_data';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/io_file_utils.dart';
import '../utils/platform_parsers.dart';

/// Scans Linux installed applications (.desktop entries, dpkg/apt, pacman, dnf, flatpak, snap),
/// distinguishes User Installed Apps vs System Apps, locates XDG/Flatpak/Snap app data & cache,
/// and discovers orphaned leftovers.
class LinuxAppScanner {
  String get _homeDir => Platform.environment['HOME'] ?? '/home';
  String get _xdgConfigHome =>
      Platform.environment['XDG_CONFIG_HOME'] ?? '$_homeDir/.config';
  String get _xdgDataHome =>
      Platform.environment['XDG_DATA_HOME'] ?? '$_homeDir/.local/share';
  String get _xdgStateHome =>
      Platform.environment['XDG_STATE_HOME'] ?? '$_homeDir/.local/state';
  String get _xdgCacheHome =>
      Platform.environment['XDG_CACHE_HOME'] ?? '$_homeDir/.cache';

  static List<String> get builtInWhitelist =>
      _ignoredLinuxOrphanFolders.toList()..sort();

  final Map<String, ({DateTime fetchedAt, List<String> childPaths})>
      _vendorSubdirCache = {};

  Future<List<String>> _listImmediateChildPaths(String dirPath) async {
    final now = DateTime.now();
    final cached = _vendorSubdirCache[dirPath];
    if (cached != null && now.difference(cached.fetchedAt).inSeconds < 20) {
      return cached.childPaths;
    }
    final result = <String>[];
    try {
      await for (final child in Directory(dirPath).list(followLinks: false)) {
        result.add(child.path);
      }
    } catch (_) {}
    _vendorSubdirCache[dirPath] = (fetchedAt: now, childPaths: result);
    return result;
  }

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
    'pipewire',
    'wireplumber',
    'systemd',
    'dbus-1',
    'environment.d',
    'ibus',
    'fcitx',
    'fcitx5',
    'fontconfig',
    'fonts',
    'menus',
    'mime',
    'icons',
    'themes',
    'backgrounds',
    'sounds',
    'templates',
    'applications',
    'desktop-directories',
    'keyrings',
    'gvfs-metadata',
    'gvfs',
    'trash',
    'tracker',
    'tracker3',
    'evolution',
    'gnome-session',
    'gnome-shell',
    'gnome-control-center',
    'nautilus',
    'kde',
    'kded5',
    'kded6',
    'plasma',
    'baloo',
    'akonadi',
    'kwalletd',
    'xfce4',
    'cinnamon',
    'mate',
    'lxqt',
    'wayland',
    'xorg',
    'mutter',
    'xdg-desktop-portal',
    'autostart',
    'user-dirs.dirs',
    'user-dirs.locale',
    'mimeapps.list',
    'recently-used.xbel',
    'colord',
    'icc',
    'flatpak',
    'snapd',
    'appstream',
    'fwupd',
    'webkitgtk',
    'pki',
    'ssl',
    'gnupg',
    'ssh',
    'pip',
    'pipx',
    'uv',
    'conda',
    'mamba',
    'poetry',
    'pyenv',
    'npm',
    'pnpm',
    'yarn',
    'bun',
    'deno',
    'nvm',
    'fnm',
    'cargo',
    'rustup',
    'go',
    'go-build',
    'gradle',
    'm2',
    'maven',
    'dotnet',
    'nuget',
    'composer',
    'flutter',
    'dart',
    'dart-tool',
    'pub-cache',
    'android',
    'huggingface',
    'torch',
    'matplotlib',
    'jupyter',
    'ipython',
    'texmf',
    'texlive',
    'luatex-cache',
    'mesa_shader_cache',
    'mesa_shader_cache_db',
    'radv_builtin_shaders',
    'nvidia',
    'nv',
    'vulkan',
    'shadercache',
    'gstreamer-1.0',
    'glib-2.0',
    'gio-2.0',
    'goa-1.0',
    'thumbnails',
    'appcleaner',
    'app_cleaner',
    'com.yin.appcleaner',
  };

  /// Scans all installed applications on Linux using bulk package-manager
  /// queries (1x `dpkg -S` + 1x `dpkg-query`) and concurrent icon/size loading
  /// so Ubuntu/Debian/Arch/Fedora app lists load in under a second.
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

    final defaultPkgSource = await _detectPrimaryDistroSource();

    // Phase 1: Collect and parse all visible .desktop entries in memory (no subprocesses)
    final seenDesktopIds = <String>{};
    final parsedEntries = <({
      File file,
      String desktopId,
      bool isUserDir,
      InstallSource defaultSource,
      Map<String, String> fields,
      String execBinary,
    })>[];

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

        String content;
        try {
          content = await entity.readAsString();
        } catch (_) {
          continue;
        }

        final fields = PlatformParsers.parseDesktopEntry(content);
        if (fields['NoDisplay']?.toLowerCase() == 'true' ||
            fields['Hidden']?.toLowerCase() == 'true') {
          continue;
        }
        final rawExec = fields['Exec'] ?? '';
        if (rawExec.isEmpty) continue;

        parsedEntries.add((
          file: entity,
          desktopId: desktopId,
          isUserDir: dirEntry.isUserDir,
          defaultSource: dirEntry.defaultSource == InstallSource.aptDpkg
              ? defaultPkgSource
              : dirEntry.defaultSource,
          fields: fields,
          execBinary: _extractBinaryFromExec(rawExec),
        ));
      }
    }

    // Paths that need distro package ownership resolution (exclude Flatpak & Snap)
    final pathsToResolve = parsedEntries
        .where((e) =>
            e.defaultSource != InstallSource.flatpak &&
            e.defaultSource != InstallSource.snap &&
            (e.fields['X-Flatpak']?.isEmpty ?? true) &&
            (e.fields['X-SnapInstanceName']?.isEmpty ?? true))
        .map((e) => e.file.path)
        .toList();

    // Phase 2: Execute all system-level metadata queries ONCE in parallel
    final manualFuture = _fetchExplicitlyInstalledPackages();
    final runningFuture = _fetchRunningProcesses();
    final flatpakFuture = _fetchFlatpakAppMetadata();
    final ownersFuture = _batchResolvePackageOwners(
      pathsToResolve,
      defaultPkgSource,
    );
    final bulkPkgMetaFuture = _fetchBulkPackageMetadata(defaultPkgSource);

    final manualPackages = await manualFuture;
    final runningProcesses = await runningFuture;
    final flatpakMeta = await flatpakFuture;
    final ownerMap = await ownersFuture;
    final bulkPkgMeta = await bulkPkgMetaFuture;

    // Phase 3: Build InstalledApp objects concurrently in bounded batches
    final apps = <InstalledApp>[];
    const batchSize = 12;
    for (var i = 0; i < parsedEntries.length; i += batchSize) {
      final chunk = parsedEntries.sublist(
        i,
        (i + batchSize).clamp(0, parsedEntries.length),
      );
      final built = await Future.wait(
        chunk.map(
          (entry) => _buildAppFromParsedEntry(
            file: entry.file,
            desktopId: entry.desktopId,
            isUserDir: entry.isUserDir,
            defaultSource: entry.defaultSource,
            fields: entry.fields,
            execBinary: entry.execBinary,
            manualPackages: manualPackages,
            runningProcesses: runningProcesses,
            flatpakMeta: flatpakMeta,
            ownerMap: ownerMap,
            bulkPkgMeta: bulkPkgMeta,
          ),
        ),
      );
      apps.addAll(built);
    }

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  Future<InstalledApp> _buildAppFromParsedEntry({
    required File file,
    required String desktopId,
    required bool isUserDir,
    required InstallSource defaultSource,
    required Map<String, String> fields,
    required String execBinary,
    required Set<String> manualPackages,
    required String runningProcesses,
    required Map<String, ({String version, int sizeBytes})> flatpakMeta,
    required Map<String, ({String packageName, InstallSource source})> ownerMap,
    required Map<String, ({String version, int sizeBytes})> bulkPkgMeta,
  }) async {
    final name = fields['Name'] ?? desktopId;
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
      final owner = ownerMap[file.path];
      if (owner != null) {
        packageName = owner.packageName;
        identifier = packageName;
        source = owner.source;
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
    if (source == InstallSource.flatpak) {
      final fp = flatpakMeta[identifier];
      if (fp != null) {
        if (fp.version.isNotEmpty) version = fp.version;
        appSize = fp.sizeBytes;
      }
      if (appSize == 0) {
        appSize = await _measureFlatpakFallbackSize(identifier);
      }
    } else if (source == InstallSource.snap) {
      final resolvedSnap = packageName ?? identifier;
      appSize = await _measureSnapSize(resolvedSnap);
    } else if (packageName != null &&
        (source == InstallSource.aptDpkg ||
            source == InstallSource.pacman ||
            source == InstallSource.dnfRpm)) {
      final cached = bulkPkgMeta[packageName];
      if (cached != null) {
        if (cached.version.isNotEmpty) version = cached.version;
        appSize = cached.sizeBytes;
      } else {
        final meta = await _queryPackageVersionAndSize(packageName, source);
        if (meta.version.isNotEmpty) version = meta.version;
        appSize = meta.sizeBytes;
      }
      // If DEB package omitted Installed-Size in DEBIAN/control, sum via dpkg -L
      if (appSize == 0 && source == InstallSource.aptDpkg) {
        appSize = await _sumDpkgOwnedFiles(packageName);
      }
    }

    // Fallback for AppImage, /opt/* bundles, or standalone local binaries
    if (appSize == 0) {
      appSize = await _measureBinaryOrBundleSize(execBinary);
    }

    final isSelf = IoFileUtils.isSelfApplication(
      installPath: file.path,
      identifier: identifier,
      name: name,
      executablePath: execBinary,
    );

    final binBase = FormatUtils.basename(execBinary);
    final isRunning =
        isSelf || (binBase.length >= 3 && runningProcesses.contains(binBase));
    final iconBytes =
        isSelf ? null : await _resolveLinuxIconBytes(fields['Icon'] ?? '');

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
      isSelfApp: isSelf,
      iconBytes: iconBytes,
      isRunning: isRunning,
    );
  }

  /// Resolves owning packages for all [paths] in ONE single `dpkg -S` / `pacman -Qo` / `rpm -qf` invocation.
  Future<Map<String, ({String packageName, InstallSource source})>>
      _batchResolvePackageOwners(
    List<String> paths,
    InstallSource distroSource,
  ) async {
    final result = <String, ({String packageName, InstallSource source})>{};
    if (paths.isEmpty) return result;

    try {
      if (distroSource == InstallSource.aptDpkg) {
        // Single dpkg -S call reads /var/lib/dpkg/info/*.list ONCE instead of N times
        final res = await Process.run('dpkg', ['-S', ...paths]);
        final stdoutStr = res.stdout as String;
        for (final line in stdoutStr.split('\n')) {
          final sep = line.indexOf(': ');
          if (sep <= 0) continue;
          final rawPkg = line.substring(0, sep).split(',').first.trim();
          final pkg = rawPkg.split(':').first.trim();
          final filePath = line.substring(sep + 2).trim();
          if (pkg.isNotEmpty && filePath.isNotEmpty) {
            result[filePath] = (
              packageName: pkg,
              source: InstallSource.aptDpkg,
            );
          }
        }
      } else if (distroSource == InstallSource.pacman) {
        final res = await Process.run(
          'pacman',
          ['-Qo', ...paths],
          environment: {'LC_ALL': 'C'},
        );
        final reg = RegExp(r'^(.+?)\s+is owned by\s+(\S+)');
        for (final line in (res.stdout as String).split('\n')) {
          final m = reg.firstMatch(line.trim());
          if (m != null) {
            result[m.group(1)!.trim()] = (
              packageName: m.group(2)!.trim(),
              source: InstallSource.pacman,
            );
          }
        }
      } else if (distroSource == InstallSource.dnfRpm) {
        for (final p in paths) {
          final res = await Process.run(
            'rpm',
            ['-qf', '--queryformat', '%{NAME}', p],
          );
          if (res.exitCode == 0) {
            final pkg = (res.stdout as String).trim();
            if (pkg.isNotEmpty && !pkg.contains('not owned')) {
              result[p] = (packageName: pkg, source: InstallSource.dnfRpm);
            }
          }
        }
      }
    } catch (_) {}

    return result;
  }

  /// Fetches version & installed size for ALL installed distro packages in ONE single call.
  Future<Map<String, ({String version, int sizeBytes})>>
      _fetchBulkPackageMetadata(InstallSource distroSource) async {
    final map = <String, ({String version, int sizeBytes})>{};
    try {
      if (distroSource == InstallSource.aptDpkg) {
        final res = await Process.run('dpkg-query', [
          '-W',
          r'-f=${Package}\t${Version}\t${Installed-Size}\n',
        ]);
        if (res.exitCode == 0) {
          for (final line in (res.stdout as String).split('\n')) {
            final parts = line.trim().split('\t');
            if (parts.length < 2) continue;
            final pkg = parts[0].split(':').first.trim();
            final ver = parts[1].trim();
            final kb = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
            if (pkg.isNotEmpty) {
              map[pkg] = (version: ver, sizeBytes: kb * 1024);
            }
          }
        }
      } else if (distroSource == InstallSource.dnfRpm) {
        final res = await Process.run('rpm', [
          '-qa',
          '--queryformat',
          r'%{NAME}\t%{VERSION}\t%{SIZE}\n',
        ]);
        if (res.exitCode == 0) {
          for (final line in (res.stdout as String).split('\n')) {
            final parts = line.trim().split('\t');
            if (parts.length < 2) continue;
            final pkg = parts[0].trim();
            final ver = parts[1].trim();
            final bytes = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
            if (pkg.isNotEmpty) {
              map[pkg] = (version: ver, sizeBytes: bytes);
            }
          }
        }
      }
    } catch (_) {}
    return map;
  }

  /// Resolves raster icon bytes (.png/.jpg/.webp) from a `.desktop` `Icon=` entry.
  Future<Uint8List?> _resolveLinuxIconBytes(String iconSpec) async {
    final trimmed = iconSpec.trim();
    if (trimmed.isEmpty) return null;

    const rasterExts = ['.png', '.jpg', '.jpeg', '.webp'];

    if (trimmed.startsWith('/')) {
      final lower = trimmed.toLowerCase();
      if (rasterExts.any(lower.endsWith)) {
        final f = File(trimmed);
        if (await f.exists()) {
          try {
            return await f.readAsBytes();
          } catch (_) {}
        }
      }
      return null;
    }

    final searchDirs = <String>[
      '/usr/share/icons/hicolor/256x256/apps',
      '/usr/share/icons/hicolor/128x128/apps',
      '/usr/share/icons/hicolor/512x512/apps',
      '/usr/share/icons/hicolor/64x64/apps',
      '/usr/share/icons/hicolor/48x48/apps',
      '/usr/share/pixmaps',
      '$_xdgDataHome/icons/hicolor/256x256/apps',
      '$_xdgDataHome/icons/hicolor/128x128/apps',
      '/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps',
      '$_xdgDataHome/flatpak/exports/share/icons/hicolor/128x128/apps',
    ];

    for (final dir in searchDirs) {
      for (final ext in const ['.png', '.jpg']) {
        final candidate = File('$dir/$trimmed$ext');
        if (await candidate.exists()) {
          try {
            return await candidate.readAsBytes();
          } catch (_) {}
        }
      }
    }
    return null;
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
  Future<List<AppDataItem>> scanAppDataItems(
    InstalledApp app, {
    bool scanVendorSubfolders = true,
  }) async {
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
    final normalizedTokens = <String>{};
    for (final raw in tokens) {
      PlatformParsers.addNormalizedAppTokens(normalizedTokens, raw);
    }

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
        if (_ignoredLinuxOrphanFolders.contains(base.toLowerCase())) continue;

        final matched = tokens.any(
              (t) => base.toLowerCase() == t.toLowerCase(),
            ) ||
            PlatformParsers.matchesInstalledIdentifier(base, normalizedTokens);

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
          continue;
        }

        // Inspect 1-level vendor subfolders (e.g. ~/.config/Softdeluxe/Free Download Manager)
        if (scanVendorSubfolders &&
            entry is Directory &&
            !base.startsWith('.')) {
          final children = await _listImmediateChildPaths(entry.path);
          for (final childPath in children) {
            final childBase = FormatUtils.basename(childPath);
            if (childBase.startsWith('.')) continue;
            final childMatched = tokens.any(
                  (t) => childBase.toLowerCase() == t.toLowerCase(),
                ) ||
                PlatformParsers.matchesInstalledIdentifier(
                  childBase,
                  normalizedTokens,
                );
            if (childMatched && seenPaths.add(childPath)) {
              final size = await IoFileUtils.calculateEntitySize(childPath);
              final stat = await FileStat.stat(childPath);
              items.add(
                AppDataItem(
                  id: childPath,
                  name: '$base/$childBase',
                  path: childPath,
                  category: target.category,
                  sizeBytes: size,
                  lastModified: stat.modified,
                  isDirectory: stat.type == FileSystemEntityType.directory,
                  description: '${target.description} ($base/$childBase)',
                ),
              );
            }
          }
        }
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  /// Scans XDG directories and Flatpak/Snap user folders for orphaned leftovers on Linux.
  ///
  /// Cross-references GUI `.desktop` apps, ALL installed system/CLI packages
  /// (`dpkg-query` / `pacman` / `rpm` / `flatpak` / `snap`), and installed binaries
  /// in standard `PATH` directories, while stripping version suffixes (e.g. `LyX-2.4`
  /// -> `lyx`) so active apps and CLI tools are not falsely flagged as leftovers.
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    final installedNorms = <String>{};
    for (final app in installedApps) {
      for (final token in [
        app.identifier,
        app.name,
        app.linuxPackageName ?? '',
        FormatUtils.basename(app.executablePath),
      ]) {
        PlatformParsers.addNormalizedAppTokens(installedNorms, token);
      }
    }

    // Cross-reference all installed packages & CLI executables so non-GUI tools
    // and versioned configs (e.g. LyX-2.4, python3.12, git, vim, tmux) aren't flagged.
    final systemTokens = await Future.wait([
      _fetchAllInstalledPackageTokens(),
      _fetchInstalledPathBinaryTokens(),
    ]);
    for (final set in systemTokens) {
      installedNorms.addAll(set);
    }

    final scanTargets = <({
      String path,
      DataCategory category,
      bool directoriesOnly,
    })>[
      (
        path: _xdgConfigHome,
        category: DataCategory.preferences,
        directoriesOnly: true,
      ),
      (
        path: _xdgCacheHome,
        category: DataCategory.cache,
        directoriesOnly: true,
      ),
      (
        path: _xdgDataHome,
        category: DataCategory.appData,
        directoriesOnly: true,
      ),
      (
        path: '$_homeDir/.var/app',
        category: DataCategory.container,
        directoriesOnly: true,
      ),
      (
        path: '$_homeDir/snap',
        category: DataCategory.container,
        directoriesOnly: true,
      ),
    ];

    final grouped = <String, List<AppDataItem>>{};
    final titles = <String, String>{};

    final pendingCandidates = <({
      String path,
      String base,
      String key,
      DataCategory category,
    })>[];

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
        if (target.directoriesOnly && entry is! Directory) continue;

        final base = FormatUtils.basename(entry.path);
        final baseLower = base.toLowerCase();
        final strippedLower =
            PlatformParsers.stripVersionAndChannelSuffix(base).toLowerCase();
        if (base.startsWith('.') ||
            _ignoredLinuxOrphanFolders.contains(baseLower) ||
            _ignoredLinuxOrphanFolders.contains(strippedLower)) {
          continue;
        }

        final norm = FormatUtils.normalizeToken(base);
        if (norm.length < 3 ||
            PlatformParsers.matchesInstalledIdentifier(base, installedNorms) ||
            settings.isWhitelisted(entry.path, name: base) ||
            settings.isAssociatedWithInstalledApp(entry.path, installedApps)) {
          continue;
        }

        if (settings.scanVendorSubfolders && entry is Directory) {
          bool hasInstalledChild = false;
          final children = await _listImmediateChildPaths(entry.path);
          for (final childPath in children) {
            final childBase = FormatUtils.basename(childPath);
            if (childBase.startsWith('.')) continue;
            if (PlatformParsers.matchesInstalledIdentifier(
              childBase,
              installedNorms,
            )) {
              hasInstalledChild = true;
              break;
            }
          }
          if (hasInstalledChild) continue;
        }

        final groupKey = FormatUtils.normalizeToken(
          PlatformParsers.stripVersionAndChannelSuffix(base),
        );
        final key = groupKey.length >= 3 ? groupKey : norm;
        pendingCandidates.add((
          path: entry.path,
          base: base,
          key: key,
          category: target.category,
        ));
      }
    }

    final batchSizes = await IoFileUtils.calculateBatchSizes(
      pendingCandidates.map((c) => c.path).toList(),
      maxFilesPerFallback: 1500,
    );

    for (final c in pendingCandidates) {
      final size = batchSizes[c.path] ?? 0;
      if (size == 0) continue;
      final stat = await FileStat.stat(c.path);
      titles.putIfAbsent(c.key, () => c.base);
      grouped.putIfAbsent(c.key, () => []).add(
            AppDataItem(
              id: c.path,
              name: c.base,
              path: c.path,
              category: c.category,
              sizeBytes: size,
              lastModified: stat.modified,
              isDirectory: stat.type == FileSystemEntityType.directory,
              description:
                  'Orphaned directory not matching any installed Linux package or .desktop entry',
              selected: false,
            ),
          );
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
              'No matching installed DEB/RPM/Pacman/Flatpak/Snap package or CLI binary found',
          items: list,
        ),
      );
    });
    groups.sort((a, b) => b.totalSizeBytes.compareTo(a.totalSizeBytes));
    return groups;
  }

  /// Queries all installed packages across dpkg/pacman/rpm/flatpak/snap in bulk
  /// so CLI tools and non-GUI packages are recognized during orphan scanning.
  Future<Set<String>> _fetchAllInstalledPackageTokens() async {
    final tokens = <String>{};

    Future<void> runAndCollect(String exe, List<String> args,
        {int column = 0}) async {
      try {
        final res = await Process.run(exe, args);
        if (res.exitCode != 0) return;
        for (final rawLine in (res.stdout as String).split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length <= column) continue;
          final pkg = parts[column].split(':').first.trim();
          if (pkg.isEmpty || pkg == 'Name') continue;
          PlatformParsers.addNormalizedAppTokens(tokens, pkg);
          // For packages like `lyx-common` or `libreoffice-core`, also index base stem.
          if (pkg.contains('-')) {
            final stem = pkg.split('-').first;
            if (stem.length >= 3 && stem != 'lib') {
              PlatformParsers.addNormalizedAppTokens(tokens, stem);
            }
          }
        }
      } catch (_) {}
    }

    await Future.wait([
      runAndCollect('dpkg-query', ['-W', r'-f=${Package}\n']),
      runAndCollect('pacman', ['-Qq']),
      runAndCollect('rpm', ['-qa', '--qf', r'%{NAME}\n']),
      runAndCollect('flatpak', ['list', '--columns=application']),
      runAndCollect('snap', ['list']),
    ]);

    return tokens;
  }

  /// Collects installed executable names from standard PATH directories.
  Future<Set<String>> _fetchInstalledPathBinaryTokens() async {
    final tokens = <String>{};
    final binDirs = [
      '/usr/bin',
      '/usr/local/bin',
      '$_homeDir/.local/bin',
      '/snap/bin',
    ];
    for (final path in binDirs) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          final name = FormatUtils.basename(entity.path);
          if (name.length >= 3) {
            PlatformParsers.addNormalizedAppTokens(tokens, name);
          }
        }
      } catch (_) {}
    }
    return tokens;
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
          int sizeBytes = kb * 1024;
          // Some DEB packages omit Installed-Size in DEBIAN/control; sum owned files via dpkg -L
          if (sizeBytes == 0) {
            sizeBytes = await _sumDpkgOwnedFiles(packageName);
          }
          return (version: ver, sizeBytes: sizeBytes);
        }
      } else if (source == InstallSource.pacman) {
        final res = await Process.run(
          'pacman',
          ['-Qi', packageName],
          environment: {'LC_ALL': 'C'},
        );
        if (res.exitCode == 0) {
          String ver = '';
          int sizeBytes = 0;
          for (final line in (res.stdout as String).split('\n')) {
            if (line.startsWith('Version')) {
              ver = line.split(':').skip(1).join(':').trim();
            } else if (line.startsWith('Installed Size')) {
              sizeBytes = FormatUtils.parseHumanSize(
                line.split(':').skip(1).join(':').trim(),
              );
            }
          }
          return (version: ver, sizeBytes: sizeBytes);
        }
      } else if (source == InstallSource.dnfRpm) {
        final res = await Process.run(
          'rpm',
          ['-q', '--queryformat', r'%{VERSION}\t%{SIZE}', packageName],
        );
        if (res.exitCode == 0) {
          final parts = (res.stdout as String).trim().split('\t');
          final ver = parts.isNotEmpty ? parts[0] : '';
          final bytes = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
          return (version: ver, sizeBytes: bytes);
        }
      }
    } catch (_) {}
    return (version: '', sizeBytes: 0);
  }

  Future<int> _sumDpkgOwnedFiles(String packageName) async {
    try {
      final res = await Process.run('dpkg', ['-L', packageName]);
      if (res.exitCode != 0) return 0;
      int total = 0;
      for (final line in (res.stdout as String).split('\n')) {
        final p = line.trim();
        if (p.isEmpty) continue;
        final stat = await FileStat.stat(p);
        if (stat.type == FileSystemEntityType.file) {
          total += stat.size;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, ({String version, int sizeBytes})>>
      _fetchFlatpakAppMetadata() async {
    final map = <String, ({String version, int sizeBytes})>{};
    try {
      final res = await Process.run(
        'flatpak',
        ['list', '--app', '--columns=application,version,size'],
        environment: {'LC_ALL': 'C'},
      );
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final parts = line.trim().split('\t');
          if (parts.isEmpty || parts[0].trim().isEmpty) continue;
          final appId = parts[0].trim();
          final ver = parts.length >= 2 ? parts[1].trim() : '';
          final sz = parts.length >= 3
              ? FormatUtils.parseHumanSize(parts[2].trim())
              : 0;
          map[appId] = (version: ver, sizeBytes: sz);
        }
      }
    } catch (_) {}
    return map;
  }

  Future<int> _measureFlatpakFallbackSize(String appId) async {
    for (final path in [
      '/var/lib/flatpak/app/$appId',
      '$_xdgDataHome/flatpak/app/$appId',
    ]) {
      if (await Directory(path).exists()) {
        final size = await IoFileUtils.calculateEntitySize(path);
        if (size > 0) return size;
      }
    }
    return 0;
  }

  Future<int> _measureSnapSize(String snapName) async {
    final currentDir = '/snap/$snapName/current';
    if (await Directory(currentDir).exists()) {
      final size = await IoFileUtils.calculateEntitySize(currentDir);
      if (size > 0) return size;
    }
    return 0;
  }

  Future<int> _measureBinaryOrBundleSize(String execBinary) async {
    if (execBinary.isEmpty) return 0;
    String resolvedPath = execBinary;
    if (!resolvedPath.startsWith('/')) {
      try {
        final whichRes = await Process.run('which', [resolvedPath]);
        if (whichRes.exitCode == 0) {
          resolvedPath = (whichRes.stdout as String).trim().split('\n').first;
        }
      } catch (_) {}
    }
    if (!resolvedPath.startsWith('/')) return 0;

    try {
      final file = File(resolvedPath);
      if (await file.exists()) {
        final realPath = await file.resolveSymbolicLinks();
        // If installed under /opt/<AppDir>/..., measure the entire /opt/<AppDir> bundle
        if (realPath.startsWith('/opt/')) {
          final segments = realPath.split('/');
          if (segments.length >= 3) {
            final optRoot = '/opt/${segments[2]}';
            if (await Directory(optRoot).exists()) {
              return await IoFileUtils.calculateEntitySize(optRoot);
            }
          }
        }
        // AppImage or standalone binary
        return await File(realPath).length();
      }
    } catch (_) {}
    return 0;
  }

  Future<String> _fetchRunningProcesses() async {
    try {
      final res = await Process.run('ps', ['-axo', 'comm']);
      if (res.exitCode == 0) return res.stdout as String;
    } catch (_) {}
    return '';
  }
}
