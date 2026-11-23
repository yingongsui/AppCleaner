import 'dart:io';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
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
        linuxScanner = linuxScanner ??
            LinuxAppScanner(
              dependencyAnalyzer:
                  linuxDependencyAnalyzer ?? LinuxDependencyAnalyzer(),
            ),
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

  Future<void> ensureAppDataScanned(InstalledApp app) async {
    if (app.platform == DesktopPlatformType.macos && Platform.isMacOS) {
      app.dataItems = await macScanner.scanAppDataItems(app);
    } else if (app.platform == DesktopPlatformType.linux && Platform.isLinux) {
      app.dataItems = await linuxScanner.scanAppDataItems(app);
      app.linuxDependencies =
          await linuxDependencyAnalyzer.analyzeDependencies(app);
    } else if (app.platform == DesktopPlatformType.windows &&
        Platform.isWindows) {
      app.dataItems = await windowsScanner.scanAppDataItems(app);
    }
    app.dataScanned = true;
  }

  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) async {
    if (Platform.isMacOS) {
      return macScanner.scanOrphanedLeftovers(installedApps);
    } else if (Platform.isLinux) {
      return linuxScanner.scanOrphanedLeftovers(installedApps);
    } else if (Platform.isWindows) {
      return windowsScanner.scanOrphanedLeftovers(installedApps);
    }
    return [];
  }

  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
  }) async {
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
      final ok = await _deleteItemOrRegistry(item, logs: logs);
      if (ok) {
        freed += item.sizeBytes;
        deletedPaths.add(item.path);
        app.dataItems.remove(item);
      } else {
        failedPaths.add(item.path);
      }
    }

    if (Platform.isMacOS &&
        !cacheOnly &&
        targets.any((t) => t.category == DataCategory.preferences)) {
      try {
        await Process.run('defaults', ['delete', app.identifier]);
        logs.add(
          'Flushed macOS cfprefsd preference cache (defaults delete ${app.identifier})',
        );
      } catch (_) {}
    }

    final actionLabel =
        cacheOnly ? 'Clear Cache Only' : 'Clear All App Data (Reset App)';
    return CleanActionResult(
      success: failedPaths.isEmpty,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      failedPaths: failedPaths,
      commandLogs: logs,
      summaryMessage: failedPaths.isEmpty
          ? 'Completed "$actionLabel": cleaned ${deletedPaths.length} items, freed ${FormatUtils.formatBytes(freed)} (app binary kept intact).'
          : 'Cleaned ${deletedPaths.length} items (freed ${FormatUtils.formatBytes(freed)}), ${failedPaths.length} items skipped due to permissions.',
    );
  }

  Future<CleanActionResult> uninstallApp({
    required InstalledApp app,
    required bool removeSelectedData,
    required bool removeSelectedLinuxDeps,
    bool moveToTrashOnMac = true,
  }) async {
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
        final ok = await _deleteItemOrRegistry(item, logs: logs);
        if (ok) {
          freedBytes += item.sizeBytes;
          deletedPaths.add(item.path);
          app.dataItems.remove(item);
        } else {
          failedPaths.add(item.path);
        }
      }
    }

    bool appRemoved = false;

    if (Platform.isMacOS) {
      appRemoved = await _uninstallMacAppBundle(
        app,
        moveToTrash: moveToTrashOnMac,
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
    List<OrphanLeftoverGroup> groups,
  ) async {
    int freed = 0;
    final deletedPaths = <String>[];
    final failedPaths = <String>[];
    final logs = <String>[];

    for (final group in groups) {
      final selectedItems = group.items.where((i) => i.selected).toList();
      for (final item in selectedItems) {
        final ok = await _deleteItemOrRegistry(item, logs: logs);
        if (ok) {
          freed += item.sizeBytes;
          deletedPaths.add(item.path);
          group.items.remove(item);
        } else {
          failedPaths.add(item.path);
        }
      }
    }

    return CleanActionResult(
      success: failedPaths.isEmpty,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      failedPaths: failedPaths,
      commandLogs: logs,
      summaryMessage: failedPaths.isEmpty
          ? 'Removed ${deletedPaths.length} orphaned leftover items, freeing ${FormatUtils.formatBytes(freed)}.'
          : 'Removed ${deletedPaths.length} orphaned items (freed ${FormatUtils.formatBytes(freed)}), ${failedPaths.length} failed.',
    );
  }

  Future<bool> terminateRunningApp(InstalledApp app) async {
    try {
      if (Platform.isMacOS) {
        final exeName = FormatUtils.basename(app.executablePath);
        final res = await Process.run('pkill', ['-f', app.installPath]);
        if (res.exitCode != 0 && exeName.isNotEmpty) {
          await Process.run('killall', [exeName]);
        }
        return true;
      } else if (Platform.isLinux) {
        final exeName = FormatUtils.basename(app.executablePath);
        if (exeName.isNotEmpty) {
          await Process.run('pkill', ['-f', exeName]);
        }
        return true;
      } else if (Platform.isWindows) {
        final exeName = FormatUtils.basename(app.executablePath);
        if (exeName.isNotEmpty) {
          await Process.run('taskkill', ['/F', '/IM', exeName]);
        }
        return true;
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
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final parent = File(path).parent.path;
        await Process.run('xdg-open', [parent]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      }
    } catch (_) {}
  }

  Future<bool> _deleteItemOrRegistry(
    AppDataItem item, {
    List<String>? logs,
  }) async {
    if (item.isRegistryKey) {
      if (Platform.isWindows) {
        return windowsScanner.deleteRegistryKey(item.path, logs: logs);
      }
      logs?.add('Cleaned registry key: ${item.path}');
      return true;
    }
    return _deleteFileSystemPath(item.path);
  }

  Future<bool> _uninstallMacAppBundle(
    InstalledApp app, {
    required bool moveToTrash,
    required List<String> logs,
  }) async {
    final path = app.installPath;
    if (!await Directory(path).exists()) return false;

    if (moveToTrash) {
      final trashDir = '${Platform.environment['HOME'] ?? ''}/.Trash';
      if (await Directory(trashDir).exists()) {
        final baseName = FormatUtils.basename(path);
        var destPath = '$trashDir/$baseName';
        if (await Directory(destPath).exists()) {
          destPath =
              '$trashDir/${baseName}_${DateTime.now().millisecondsSinceEpoch}.app';
        }
        try {
          await Directory(path).rename(destPath);
          logs.add('Moved application bundle to Trash: $destPath');
          return true;
        } catch (_) {}
      }
    }

    final ok = await _deleteFileSystemPath(path);
    if (ok) {
      logs.add('Permanently deleted application bundle: $path');
      return true;
    }

    try {
      final escaped = path.replaceAll('"', r'\"');
      final script =
          'do shell script "rm -rf \\"$escaped\\"" with administrator privileges';
      final res = await Process.run('osascript', ['-e', script]);
      if (res.exitCode == 0) {
        logs.add('Deleted application bundle with administrator privileges: $path');
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<bool> _uninstallLinuxApp({
    required InstalledApp app,
    required List<LinuxDependencyPackage> selectedDependencies,
    required List<String> logs,
    required List<String> removedPackages,
  }) async {
    if (app.installSource == InstallSource.appImageOrOpt &&
        app.linuxPackageName == null) {
      final ok = await _deleteFileSystemPath(app.installPath);
      if (app.executablePath.isNotEmpty &&
          app.executablePath
              .startsWith(Platform.environment['HOME'] ?? '/home')) {
        await _deleteFileSystemPath(app.executablePath);
      }
      logs.add('Deleted local desktop entry & binary: ${app.installPath}');
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

  Future<bool> _deleteFileSystemPath(String path) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return true;
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
