import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/io_file_utils.dart';
import '../utils/platform_parsers.dart';
import 'linux_dependency_analyzer.dart';
import 'linux_scanner.dart';
import 'macos_scanner.dart';
import 'windows_scanner.dart';

/// Native desktop (`dart:io`) backend implementation for macOS, Linux, and Windows.
/// Contains zero Web or mock dependencies.
class AppCleanerPlatformBackend {
  final MacOsAppScanner macScanner;
  final LinuxAppScanner linuxScanner;
  final WindowsAppScanner windowsScanner;
  final LinuxDependencyAnalyzer linuxDependencyAnalyzer;

  AppCleanerPlatformBackend({
    MacOsAppScanner? macScanner,
    LinuxAppScanner? linuxScanner,
    WindowsAppScanner? windowsScanner,
    LinuxDependencyAnalyzer? linuxDependencyAnalyzer,
  })  : linuxDependencyAnalyzer =
            linuxDependencyAnalyzer ?? LinuxDependencyAnalyzer(),
        macScanner = macScanner ?? MacOsAppScanner(),
        linuxScanner = linuxScanner ?? LinuxAppScanner(),
        windowsScanner = windowsScanner ?? WindowsAppScanner();

  Future<List<InstalledApp>> scanInstalledApps({
    DesktopPlatformType? filterPlatform,
  }) async {
    List<InstalledApp> apps = [];
    if (Platform.isMacOS) {
      apps = await macScanner.scanInstalledApps();
    } else if (Platform.isLinux) {
      apps = await linuxScanner.scanInstalledApps();
    } else if (Platform.isWindows) {
      apps = await windowsScanner.scanInstalledApps();
    }

    if (filterPlatform != null) {
      return apps.where((a) => a.platform == filterPlatform).toList();
    }
    return apps;
  }

  Future<void> ensureAppDataScanned(
    InstalledApp app, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    List<AppDataItem> items = app.dataItems;
    if (app.platform == DesktopPlatformType.macos && Platform.isMacOS) {
      items = await macScanner.scanAppDataItems(
        app,
        scanVendorSubfolders: settings.scanVendorSubfolders,
      );
    } else if (app.platform == DesktopPlatformType.linux && Platform.isLinux) {
      items = await linuxScanner.scanAppDataItems(
        app,
        scanVendorSubfolders: settings.scanVendorSubfolders,
      );
      app.linuxDependencies =
          await linuxDependencyAnalyzer.analyzeDependencies(app);
    } else if (app.platform == DesktopPlatformType.windows &&
        Platform.isWindows) {
      items = await windowsScanner.scanAppDataItems(
        app,
        scanVendorSubfolders: settings.scanVendorSubfolders,
      );
    }

    // Remove any user-whitelisted paths/names
    items.removeWhere(
      (item) => settings.isWhitelisted(item.path, name: item.name),
    );

    // Inject manual associations configured by the user for this app
    final existingPaths = items.map((e) => e.path.toLowerCase()).toSet();
    for (final assoc in settings.associationsForApp(app)) {
      if (settings.isWhitelisted(assoc.path, name: assoc.label)) continue;
      if (!existingPaths.add(assoc.path.toLowerCase())) continue;

      if (assoc.category == DataCategory.registry) {
        items.add(
          AppDataItem(
            id: 'reg:${assoc.path}',
            name: assoc.label,
            path: assoc.path,
            category: DataCategory.registry,
            sizeBytes: 16 * 1024,
            isDirectory: false,
            description: 'Manually associated Registry key',
            selected: true,
          ),
        );
      } else {
        final type =
            await FileSystemEntity.type(assoc.path, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          final size =
              await IoFileUtils.calculateEntitySize(assoc.path, maxFiles: 3000);
          final modified = await IoFileUtils.getLastModified(assoc.path);
          items.add(
            AppDataItem(
              id: assoc.path,
              name: assoc.label,
              path: assoc.path,
              category: assoc.category,
              sizeBytes: size,
              lastModified: modified,
              isDirectory: type == FileSystemEntityType.directory,
              description: 'Manually associated with ${app.name}',
              selected: true,
            ),
          );
        }
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    app.dataItems = items;
    app.dataScanned = true;
  }

  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    if (Platform.isMacOS) {
      return macScanner.scanOrphanedLeftovers(
        installedApps,
        settings: settings,
      );
    } else if (Platform.isLinux) {
      return linuxScanner.scanOrphanedLeftovers(
        installedApps,
        settings: settings,
      );
    } else if (Platform.isWindows) {
      return windowsScanner.scanOrphanedLeftovers(
        installedApps,
        settings: settings,
      );
    }
    return [];
  }

  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
    bool moveToTrash = true,
  }) async {
    if (app.isSelfApp) {
      return const CleanActionResult(
        success: false,
        deletedCount: 0,
        freedBytes: 0,
        summaryMessage:
            'Operation blocked: AppCleaner is self-locked to protect itself while running.',
      );
    }

    final logs = <String>[];
    if (terminateIfRunning && app.isRunning) {
      final stopped = await terminateRunningApp(app);
      if (stopped) {
        logs.add('Terminated running process: ${app.name}');
        app.isRunning = false;
      }
    }

    final targets = app.dataItems.where((item) {
      if (cacheOnly && !item.isCacheLike) return false;
      if (onlySelected && !item.selected) return false;
      return true;
    }).toList();

    if (targets.isEmpty) {
      return const CleanActionResult(
        success: true,
        deletedCount: 0,
        freedBytes: 0,
        summaryMessage: 'No data items selected to clean.',
      );
    }

    int freed = 0;
    final deletedPaths = <String>[];
    final failedPaths = <String>[];

    for (final item in targets) {
      final ok = await _deleteItemOrRegistry(
        item,
        moveToTrash: moveToTrash,
        logs: logs,
      );
      if (ok) {
        freed += item.sizeBytes;
        deletedPaths.add(item.path);
        app.dataItems.remove(item);
      } else {
        failedPaths.add(item.path);
      }
    }

    if (Platform.isMacOS && !cacheOnly) {
      await _flushMacPreferencesCache(app, targets, logs);
    }

    final actionLabel =
        cacheOnly ? 'Clear Cache Only' : 'Clear All App Data (Reset App)';
    final modeVerb =
        moveToTrash ? 'moved to System Trash' : 'permanently deleted';
    return CleanActionResult(
      success: failedPaths.isEmpty,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      failedPaths: failedPaths,
      commandLogs: logs,
      summaryMessage: failedPaths.isEmpty
          ? 'Completed "$actionLabel": ${deletedPaths.length} items $modeVerb (${FormatUtils.formatBytes(freed)}, app binary kept intact).'
          : '${deletedPaths.length} items $modeVerb (${FormatUtils.formatBytes(freed)}), ${failedPaths.length} items skipped due to permissions.',
    );
  }

  Future<CleanActionResult> uninstallApp({
    required InstalledApp app,
    required bool removeSelectedData,
    required bool removeSelectedLinuxDeps,
    bool moveToTrash = true,
  }) async {
    if (app.isSelfApp) {
      return const CleanActionResult(
        success: false,
        deletedCount: 0,
        freedBytes: 0,
        summaryMessage:
            'Operation blocked: AppCleaner cannot uninstall itself while running.',
      );
    }

    if (app.isSystemApp) {
      return const CleanActionResult(
        success: false,
        deletedCount: 0,
        freedBytes: 0,
        summaryMessage:
            'System applications are protected by the OS. You can clear their cache or reset their data, but cannot uninstall the binary.',
      );
    }

    final logs = <String>[];
    final deletedPaths = <String>[];
    final failedPaths = <String>[];
    final removedPackages = <String>[];
    int freedBytes = 0;

    if (app.isRunning) {
      await terminateRunningApp(app);
      app.isRunning = false;
      logs.add('Stopped running process: ${app.name}');
    }

    if (removeSelectedData) {
      final selectedData = app.dataItems.where((d) => d.selected).toList();
      for (final item in selectedData) {
        final ok = await _deleteItemOrRegistry(
          item,
          moveToTrash: moveToTrash,
          logs: logs,
        );
        if (ok) {
          freedBytes += item.sizeBytes;
          deletedPaths.add(item.path);
          app.dataItems.remove(item);
        } else {
          failedPaths.add(item.path);
        }
      }
      if (Platform.isMacOS) {
        await _flushMacPreferencesCache(app, selectedData, logs);
      }
    }

    bool appRemoved = false;

    if (Platform.isMacOS) {
      appRemoved = await _uninstallMacAppBundle(
        app,
        moveToTrash: moveToTrash,
        logs: logs,
      );
      if (appRemoved) {
        freedBytes += app.appSizeBytes;
        deletedPaths.add(app.installPath);
      } else {
        failedPaths.add(app.installPath);
      }
    } else if (Platform.isLinux) {
      final selectedDeps = removeSelectedLinuxDeps
          ? app.linuxDependencies.where((d) => d.selected).toList()
          : <LinuxDependencyPackage>[];
      appRemoved = await _uninstallLinuxApp(
        app: app,
        selectedDependencies: selectedDeps,
        moveToTrash: moveToTrash,
        logs: logs,
        removedPackages: removedPackages,
      );
      if (appRemoved) {
        freedBytes += app.appSizeBytes;
        for (final dep in selectedDeps) {
          freedBytes += dep.sizeBytes;
        }
        deletedPaths.add(app.installPath);
      } else {
        failedPaths.add(app.installPath);
      }
    } else if (Platform.isWindows) {
      appRemoved = await _uninstallWindowsApp(app, logs: logs);
      if (appRemoved) {
        freedBytes += app.appSizeBytes;
        deletedPaths.add(app.installPath);
      } else {
        failedPaths.add(app.installPath);
      }
    }

    final depSummary = removedPackages.length > 1
        ? ' (including ${removedPackages.length - 1} additional libraries)'
        : '';

    return CleanActionResult(
      success: appRemoved && failedPaths.isEmpty,
      deletedCount: deletedPaths.length,
      freedBytes: freedBytes,
      deletedPaths: deletedPaths,
      failedPaths: failedPaths,
      removedPackages: removedPackages,
      commandLogs: logs,
      summaryMessage: appRemoved
          ? 'Uninstalled ${app.name}$depSummary and removed associated leftovers, freeing ${FormatUtils.formatBytes(freedBytes)}.'
          : 'Uninstallation of ${app.name} requires administrator confirmation; cleaned ${deletedPaths.length} associated leftover items.',
    );
  }

  Future<CleanActionResult> cleanOrphanLeftovers(
    List<OrphanLeftoverGroup> groups, {
    bool moveToTrash = true,
  }) async {
    int freed = 0;
    final deletedPaths = <String>[];
    final failedPaths = <String>[];
    final logs = <String>[];

    for (final group in groups) {
      final selectedItems = group.items.where((i) => i.selected).toList();
      for (final item in selectedItems) {
        final ok = await _deleteItemOrRegistry(
          item,
          moveToTrash: moveToTrash,
          logs: logs,
        );
        if (ok) {
          freed += item.sizeBytes;
          deletedPaths.add(item.path);
          group.items.remove(item);
        } else {
          failedPaths.add(item.path);
        }
      }
    }

    final actionText = moveToTrash
        ? 'Moved ${deletedPaths.length} orphaned leftover items to System Trash'
        : 'Permanently deleted ${deletedPaths.length} orphaned leftover items';
    return CleanActionResult(
      success: failedPaths.isEmpty,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      failedPaths: failedPaths,
      commandLogs: logs,
      summaryMessage: failedPaths.isEmpty
          ? '$actionText (${FormatUtils.formatBytes(freed)}).'
          : '$actionText (${FormatUtils.formatBytes(freed)}), ${failedPaths.length} failed.',
    );
  }

  Future<bool> terminateRunningApp(InstalledApp app) async {
    if (app.isSelfApp) return false;
    const blockedGenericExecutables = {
      'sh',
      'bash',
      'zsh',
      'fish',
      'env',
      'python',
      'python3',
      'java',
      'node',
      'electron',
      'cmd.exe',
      'powershell.exe',
      'pwsh.exe',
    };
    final exeName = FormatUtils.basename(app.executablePath);
    final isSafeExeName = exeName.isNotEmpty &&
        !blockedGenericExecutables.contains(exeName.toLowerCase());

    try {
      if (Platform.isMacOS) {
        if (app.installPath.endsWith('.app')) {
          final res = await Process.run('pkill', ['-f', app.installPath]);
          if (res.exitCode == 0) return true;
        }
        if (isSafeExeName) {
          await Process.run('killall', [exeName]);
          return true;
        }
      } else if (Platform.isLinux) {
        if (app.executablePath.startsWith('/') &&
            app.executablePath.length > 5 &&
            isSafeExeName) {
          final res = await Process.run('pkill', ['-f', app.executablePath]);
          if (res.exitCode == 0) return true;
        }
        if (isSafeExeName) {
          // Use `-x` (exact process name match) instead of `-f` to avoid
          // accidentally matching substrings in unrelated command lines.
          await Process.run('pkill', ['-x', exeName]);
          return true;
        }
      } else if (Platform.isWindows) {
        if (isSafeExeName) {
          await Process.run('taskkill', ['/F', '/IM', exeName]);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> revealInFileManager(String path) async {
    try {
      if (Platform.isWindows &&
          (path.startsWith(r'HKCU\') ||
              path.startsWith(r'HKLM\') ||
              path.startsWith(r'HKEY_'))) {
        await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit',
          '/v',
          'LastKey',
          '/t',
          'REG_SZ',
          '/d',
          path,
          '/f',
        ]);
        await Process.start(
          'regedit.exe',
          [],
          mode: ProcessStartMode.detached,
        );
        return;
      }

      final isAppConfigDir = path == IoFileUtils.getAppConfigDirPath();
      if (isAppConfigDir) {
        final dir = Directory(path);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        if (Platform.isMacOS) {
          await Process.run('open', [path]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [path]);
        } else if (Platform.isWindows) {
          await Process.run('explorer.exe', [path]);
        }
        return;
      }

      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final normalized = path.length > 1 && path.endsWith('/')
            ? path.substring(0, path.length - 1)
            : path;
        final uri = Uri.file(normalized).toString();
        final dbusRes = await Process.run('dbus-send', [
          '--session',
          '--dest=org.freedesktop.FileManager1',
          '--type=method_call',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:$uri',
          'string:',
        ]);
        if (dbusRes.exitCode != 0) {
          final parent = File(normalized).parent.path;
          await Process.run('xdg-open', [parent]);
        }
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      }
    } catch (_) {}
  }

  Future<bool> _deleteItemOrRegistry(
    AppDataItem item, {
    bool moveToTrash = true,
    List<String>? logs,
  }) async {
    if (item.isRegistryKey) {
      if (Platform.isWindows) {
        return windowsScanner.deleteRegistryKey(item.path, logs: logs);
      }
      logs?.add('Cleaned registry key: ${item.path}');
      return true;
    }
    if (moveToTrash) {
      return _movePathToSystemTrash(item.path, logs: logs);
    }
    return _deleteFileSystemPath(item.path, logs: logs);
  }

  Future<bool> _uninstallMacAppBundle(
    InstalledApp app, {
    required bool moveToTrash,
    required List<String> logs,
  }) async {
    final path = app.installPath;
    if (!await Directory(path).exists()) return false;

    if (moveToTrash) {
      final movedDirectly = await _movePathToSystemTrash(path, logs: logs);
      if (movedDirectly) return true;

      // Root-owned bundles in /Applications may need Administrator privileges
      // to move into ~/.Trash — never fall through to permanent `rm -rf`!
      final home = Platform.environment['HOME'] ?? '';
      final trashDir = '$home/.Trash';
      final rawName = FormatUtils.basename(path);
      final stem = rawName.endsWith('.app')
          ? rawName.substring(0, rawName.length - 4)
          : rawName;
      var destPath = '$trashDir/$rawName';
      if (await Directory(destPath).exists()) {
        destPath =
            '$trashDir/${stem}_${DateTime.now().millisecondsSinceEpoch}.app';
      }
      try {
        final escapedSrc = path.replaceAll('"', r'\"');
        final escapedDst = destPath.replaceAll('"', r'\"');
        final script =
            'do shell script "mv -f \\"$escapedSrc\\" \\"$escapedDst\\"" with administrator privileges';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          logs.add('Moved application bundle to Trash (elevated): $destPath');
          return true;
        }
      } catch (_) {}
      return false;
    }

    final ok = await _deleteFileSystemPath(path, logs: logs);
    if (ok) return true;

    try {
      final escaped = path.replaceAll('"', r'\"');
      final script =
          'do shell script "rm -rf \\"$escaped\\"" with administrator privileges';
      final res = await Process.run('osascript', ['-e', script]);
      if (res.exitCode == 0) {
        logs.add('Permanently deleted application bundle (elevated): $path');
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<bool> _uninstallLinuxApp({
    required InstalledApp app,
    required List<LinuxDependencyPackage> selectedDependencies,
    required bool moveToTrash,
    required List<String> logs,
    required List<String> removedPackages,
  }) async {
    if (app.installSource == InstallSource.appImageOrOpt &&
        app.linuxPackageName == null) {
      final ok = moveToTrash
          ? await _movePathToSystemTrash(app.installPath, logs: logs)
          : await _deleteFileSystemPath(app.installPath, logs: logs);
      if (app.executablePath.isNotEmpty &&
          app.executablePath != app.installPath &&
          app.executablePath
              .startsWith(Platform.environment['HOME'] ?? '/home')) {
        if (moveToTrash) {
          await _movePathToSystemTrash(app.executablePath, logs: logs);
        } else {
          await _deleteFileSystemPath(app.executablePath, logs: logs);
        }
      }
      return ok;
    }

    final cmd = PlatformParsers.buildLinuxUninstallCommand(
      app: app,
      selectedDependencies: selectedDependencies,
      usePkexec: app.installSource != InstallSource.flatpak,
    );
    logs.add('Executing command: ${cmd.join(" ")}');

    try {
      final res = await Process.run(cmd.first, cmd.sublist(1));
      if (res.exitCode == 0) {
        removedPackages.add(app.linuxPackageName ?? app.identifier);
        removedPackages.addAll(selectedDependencies.map((d) => d.packageName));

        if (app.installSource == InstallSource.flatpak &&
            selectedDependencies.isNotEmpty) {
          await Process.run('flatpak', ['uninstall', '-y', '--unused']);
          logs.add('Executed flatpak uninstall -y --unused to prune runtimes');
        }
        return true;
      } else {
        logs.add('Exit code ${res.exitCode}: ${(res.stderr as String).trim()}');
      }
    } catch (e) {
      logs.add('Execution error: $e');
    }
    return false;
  }

  Future<bool> _uninstallWindowsApp(
    InstalledApp app, {
    required List<String> logs,
  }) async {
    try {
      if (app.installSource == InstallSource.msixAppx &&
          app.uninstallCommandHint != null &&
          app.uninstallCommandHint!.isNotEmpty) {
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Remove-AppxPackage -Package "${app.uninstallCommandHint}"',
        ]);
        logs.add('Executed Remove-AppxPackage ${app.uninstallCommandHint}');
        return res.exitCode == 0;
      }

      if (app.uninstallCommandHint != null &&
          app.uninstallCommandHint!.isNotEmpty) {
        logs.add('Launched application uninstaller: ${app.uninstallCommandHint}');
        await Process.start(
          'cmd',
          ['/c', app.uninstallCommandHint!],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    } catch (e) {
      logs.add('Failed to launch Windows uninstaller: $e');
    }
    return false;
  }

  Future<List<OperationLogEntry>> loadOperationHistory() async {
    try {
      final file = File(IoFileUtils.getHistoryFilePath());
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => OperationLogEntry.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveOperationHistory(List<OperationLogEntry> entries) async {
    try {
      final file = File(IoFileUtils.getHistoryFilePath());
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final payload = entries.take(500).map((e) => e.toJson()).toList();
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(payload));
    } catch (_) {}
  }

  Future<void> clearOperationHistory() async {
    try {
      final file = File(IoFileUtils.getHistoryFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<AppCleanerSettings> loadSettings() async {
    try {
      final file = File(IoFileUtils.getSettingsFilePath());
      if (!await file.exists()) return const AppCleanerSettings();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppCleanerSettings();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AppCleanerSettings();
      return AppCleanerSettings.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return const AppCleanerSettings();
    }
  }

  Future<void> saveSettings(AppCleanerSettings settings) async {
    try {
      final file = File(IoFileUtils.getSettingsFilePath());
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(settings.toJson()));
    } catch (_) {}
  }

  List<String> getBuiltInWhitelist() {
    if (Platform.isMacOS) return MacOsAppScanner.builtInWhitelist;
    if (Platform.isLinux) return LinuxAppScanner.builtInWhitelist;
    if (Platform.isWindows) return WindowsAppScanner.builtInWhitelist;
    return const [];
  }

  String getConfigDirectoryPath() => IoFileUtils.getAppConfigDirPath();

  /// Evicts cached preferences from macOS `cfprefsd` daemon RAM so reinstalled
  /// apps cannot restore deleted `.plist` settings from memory.
  Future<void> _flushMacPreferencesCache(
    InstalledApp app,
    List<AppDataItem> cleanedItems,
    List<String> logs,
  ) async {
    final domains = <String>{};
    final bid = app.identifier.trim();
    if (bid.isNotEmpty && !bid.startsWith('macos.app.')) {
      domains.add(bid);
    }
    for (final item in cleanedItems) {
      if (item.category == DataCategory.preferences &&
          item.name.toLowerCase().endsWith('.plist')) {
        final domain = item.name.substring(0, item.name.length - 6);
        if (domain.isNotEmpty) domains.add(domain);
      }
    }

    for (final domain in domains) {
      try {
        final res = await Process.run('defaults', ['delete', domain]);
        if (res.exitCode == 0) {
          logs.add('Flushed macOS cfprefsd cache (defaults delete $domain)');
        }
      } catch (_) {}
    }
  }

  /// Moves a file or directory to the operating system's native Trash / Recycle Bin
  /// so the user can restore it if needed (macOS `~/.Trash`, Linux `gio trash` /
  /// Freedesktop XDG Trash, Windows Recycle Bin).
  Future<bool> _movePathToSystemTrash(
    String path, {
    List<String>? logs,
  }) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return true;

      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        final trashDir = Directory('$home/.Trash');
        if (!await trashDir.exists()) {
          await trashDir.create(recursive: true);
        }
        final baseName = FormatUtils.basename(path);
        var destPath = '${trashDir.path}/$baseName';
        if (await FileSystemEntity.type(destPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          destPath =
              '${trashDir.path}/${DateTime.now().millisecondsSinceEpoch}_$baseName';
        }
        try {
          if (type == FileSystemEntityType.directory) {
            await Directory(path).rename(destPath);
          } else {
            await File(path).rename(destPath);
          }
          logs?.add('Moved to Trash: $destPath');
          return true;
        } catch (_) {
          final mvRes = await Process.run('mv', [path, destPath]);
          if (mvRes.exitCode == 0) {
            logs?.add('Moved to Trash: $destPath');
            return true;
          }
          logs?.add('Failed to move to Trash (permission required): $path');
          return false;
        }
      }

      if (Platform.isLinux) {
        // 1. Prefer native Freedesktop `gio trash` (GNOME / Ubuntu / Fedora)
        try {
          final gioRes = await Process.run('gio', ['trash', path]);
          if (gioRes.exitCode == 0) {
            logs?.add('Moved to Trash (gio trash): $path');
            return true;
          }
        } catch (_) {}

        // 2. Fallback to `trash-put` if installed
        try {
          final tpRes = await Process.run('trash-put', [path]);
          if (tpRes.exitCode == 0) {
            logs?.add('Moved to Trash (trash-put): $path');
            return true;
          }
        } catch (_) {}

        // 3. Built-in Freedesktop.org XDG Trash spec fallback (with .trashinfo for Restore)
        final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ??
            '${Platform.environment['HOME'] ?? '/home'}/.local/share';
        final filesDir = Directory('$xdgDataHome/Trash/files');
        final infoDir = Directory('$xdgDataHome/Trash/info');
        await filesDir.create(recursive: true);
        await infoDir.create(recursive: true);

        final baseName = FormatUtils.basename(path);
        var trashName = baseName;
        var destPath = '${filesDir.path}/$trashName';
        if (await FileSystemEntity.type(destPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          trashName = '${DateTime.now().millisecondsSinceEpoch}_$baseName';
          destPath = '${filesDir.path}/$trashName';
        }

        bool moved = false;
        try {
          if (type == FileSystemEntityType.directory) {
            await Directory(path).rename(destPath);
          } else {
            await File(path).rename(destPath);
          }
          moved = true;
        } catch (_) {
          final mvRes = await Process.run('mv', [path, destPath]);
          moved = mvRes.exitCode == 0;
        }
        if (moved) {
          final now = DateTime.now();
          String two(int n) => n.toString().padLeft(2, '0');
          final delDate =
              '${now.year}-${two(now.month)}-${two(now.day)}T${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
          final encodedPath = Uri.encodeFull(path);
          final infoFile = File('${infoDir.path}/$trashName.trashinfo');
          await infoFile.writeAsString(
            '[Trash Info]\nPath=$encodedPath\nDeletionDate=$delDate\n',
          );
          logs?.add('Moved to XDG Trash: $destPath');
          return true;
        }
        logs?.add('Failed to move to Trash: $path');
        return false;
      }

      if (Platform.isWindows) {
        final escapedPath = path.replaceAll("'", "''");
        final psMethod = type == FileSystemEntityType.directory
            ? 'DeleteDirectory'
            : 'DeleteFile';
        final psCmd =
            "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::$psMethod('$escapedPath', 'OnlyErrorDialogs', 'SendToRecycleBin')";
        final res = await Process.run(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-Command', psCmd],
        );
        if (res.exitCode == 0) {
          logs?.add('Moved to Recycle Bin: $path');
          return true;
        }
        logs?.add('Failed to move to Recycle Bin: $path');
        return false;
      }
    } catch (e) {
      logs?.add('Trash error for $path: $e');
    }
    return false;
  }

  Future<bool> _deleteFileSystemPath(
    String path, {
    List<String>? logs,
  }) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return true;
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      logs?.add('Permanently deleted: $path');
      return true;
    } catch (_) {
      return false;
    }
  }
}
