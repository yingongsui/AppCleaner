import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/platform_parsers.dart';
import 'web_mock_data.dart';

/// Web-compatible backend (no `dart:io`) for debugging and previewing the complete
/// AppCleaner UI (macOS, Linux, and Windows workflows) in a browser without Xcode.
class AppCleanerPlatformBackend {
  List<InstalledApp>? _cachedMockApps;
  List<OrphanLeftoverGroup>? _cachedMockOrphans;
  List<OperationLogEntry> _webHistory = [];
  AppCleanerSettings _webSettings = const AppCleanerSettings();

  Future<List<InstalledApp>> scanInstalledApps({
    DesktopPlatformType? filterPlatform,
  }) async {
    _cachedMockApps ??= WebMockData.buildAllSampleApps();
    if (filterPlatform != null) {
      return _cachedMockApps!
          .where((a) => a.platform == filterPlatform)
          .toList();
    }
    return List<InstalledApp>.from(_cachedMockApps!);
  }

  Future<void> ensureAppDataScanned(
    InstalledApp app, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    app.dataItems.removeWhere(
      (item) => settings.isWhitelisted(item.path, name: item.name),
    );
    final existingPaths =
        app.dataItems.map((e) => e.path.toLowerCase()).toSet();
    for (final assoc in settings.associationsForApp(app)) {
      if (existingPaths.add(assoc.path.toLowerCase()) &&
          !settings.isWhitelisted(assoc.path, name: assoc.label)) {
        app.dataItems.add(
          AppDataItem(
            id: assoc.path,
            name: assoc.label,
            path: assoc.path,
            category: assoc.category,
            sizeBytes: 512 * 1024,
            isDirectory: assoc.category != DataCategory.registry,
            description: 'Manually associated with ${app.name}',
            selected: true,
          ),
        );
      }
    }
    app.dataScanned = true;
  }

  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    _cachedMockOrphans ??= WebMockData.buildSampleOrphanGroups();
    final filtered = <OrphanLeftoverGroup>[];
    for (final g in _cachedMockOrphans!) {
      if (settings.isWhitelisted(
        g.id,
        name: g.suspectedAppName,
        identifier: g.identifier,
      )) {
        continue;
      }
      final keptItems = g.items
          .where(
            (i) =>
                !settings.isWhitelisted(
                  i.path,
                  name: i.name,
                  identifier: g.identifier,
                ) &&
                !settings.isAssociatedWithInstalledApp(i.path, installedApps),
          )
          .toList();
      if (keptItems.isNotEmpty) {
        filtered.add(
          OrphanLeftoverGroup(
            id: g.id,
            suspectedAppName: g.suspectedAppName,
            identifier: g.identifier,
            platform: g.platform,
            confidenceReason: g.confidenceReason,
            items: keptItems,
          ),
        );
      }
    }
    return filtered;
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
      app.isRunning = false;
      logs.add('[Web Simulator] Terminated running process: ${app.name}');
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
    for (final item in targets) {
      freed += item.sizeBytes;
      deletedPaths.add(item.path);
      if (item.isRegistryKey) {
        logs.add(
          '[Web Simulator] Backed up & deleted Registry key: reg delete "${item.path}" /f',
        );
      } else {
        logs.add(
          moveToTrash
              ? '[Web Simulator] Moved to System Trash: ${item.path}'
              : '[Web Simulator] Permanently deleted: ${item.path}',
        );
      }
      app.dataItems.remove(item);
    }

    final modeText = moveToTrash ? 'moved to Trash' : 'permanently deleted';
    return CleanActionResult(
      success: true,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      commandLogs: logs,
      summaryMessage: cacheOnly
          ? 'Cleared cache for ${app.name} ($modeText), freed ${FormatUtils.formatBytes(freed)} (app binary and user settings preserved).'
          : 'Reset all selected user data, registry keys & cache for ${app.name} ($modeText), freed ${FormatUtils.formatBytes(freed)} (app binary kept intact).',
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
    final deletedPaths = <String>[app.installPath];
    final removedPackages = <String>[];
    int freedBytes = app.appSizeBytes;

    if (removeSelectedData) {
      final selectedData = app.dataItems.where((d) => d.selected).toList();
      for (final item in selectedData) {
        freedBytes += item.sizeBytes;
        deletedPaths.add(item.path);
        if (item.isRegistryKey) {
          logs.add(
            '[Web Simulator] Backed up & deleted Registry key: reg delete "${item.path}" /f',
          );
        } else {
          logs.add(
            moveToTrash
                ? '[Web Simulator] Moved leftover to System Trash: ${item.path}'
                : '[Web Simulator] Permanently deleted leftover: ${item.path}',
          );
        }
        app.dataItems.remove(item);
      }
    }

    final selectedDeps = removeSelectedLinuxDeps
        ? app.linuxDependencies.where((d) => d.selected).toList()
        : <LinuxDependencyPackage>[];

    if (app.platform == DesktopPlatformType.linux || selectedDeps.isNotEmpty) {
      final cmd = PlatformParsers.buildLinuxUninstallCommand(
        app: app,
        selectedDependencies: selectedDeps,
      );
      logs.add('[Web Simulator] Executed Linux uninstall: ${cmd.join(" ")}');
      removedPackages.add(app.linuxPackageName ?? app.identifier);
      for (final dep in selectedDeps) {
        freedBytes += dep.sizeBytes;
        removedPackages.add(dep.packageName);
      }
    } else if (app.platform == DesktopPlatformType.macos) {
      logs.add(
        moveToTrash
            ? '[Web Simulator] Moved ${app.installPath} to ~/.Trash'
            : '[Web Simulator] Permanently deleted ${app.installPath}',
      );
    } else {
      logs.add(
        '[Web Simulator] Executed Windows uninstaller: ${app.uninstallCommandHint}',
      );
    }

    _cachedMockApps?.removeWhere((a) => a.id == app.id);

    return CleanActionResult(
      success: true,
      deletedCount: deletedPaths.length,
      freedBytes: freedBytes,
      deletedPaths: deletedPaths,
      removedPackages: removedPackages,
      commandLogs: logs,
      summaryMessage:
          'Uninstalled ${app.name}${selectedDeps.isNotEmpty ? " and ${selectedDeps.length} additional dependency libraries" : ""} along with selected leftovers, freeing ${FormatUtils.formatBytes(freedBytes)}.',
    );
  }

  Future<CleanActionResult> cleanOrphanLeftovers(
    List<OrphanLeftoverGroup> groups, {
    bool moveToTrash = true,
  }) async {
    int freed = 0;
    final deletedPaths = <String>[];
    final logs = <String>[];
    for (final group in groups) {
      final selectedItems = group.items.where((i) => i.selected).toList();
      for (final item in selectedItems) {
        freed += item.sizeBytes;
        deletedPaths.add(item.path);
        if (item.isRegistryKey) {
          logs.add(
            '[Web Simulator] Backed up & deleted orphaned Registry key: reg delete "${item.path}" /f',
          );
        } else {
          logs.add(
            moveToTrash
                ? '[Web Simulator] Moved orphaned leftover to System Trash: ${item.path}'
                : '[Web Simulator] Permanently deleted orphaned leftover: ${item.path}',
          );
        }
        group.items.remove(item);
      }
    }
    _cachedMockOrphans?.removeWhere((g) => g.items.isEmpty);

    return CleanActionResult(
      success: true,
      deletedCount: deletedPaths.length,
      freedBytes: freed,
      deletedPaths: deletedPaths,
      commandLogs: logs,
      summaryMessage: moveToTrash
          ? 'Moved ${deletedPaths.length} orphaned leftover items to System Trash (${FormatUtils.formatBytes(freed)}).'
          : 'Permanently deleted ${deletedPaths.length} orphaned leftover items, freeing ${FormatUtils.formatBytes(freed)}.',
    );
  }

  Future<bool> terminateRunningApp(InstalledApp app) async {
    if (app.isSelfApp) return false;
    app.isRunning = false;
    return true;
  }

  Future<void> revealInFileManager(String path) async {}

  Future<List<OperationLogEntry>> loadOperationHistory() async {
    return List<OperationLogEntry>.from(_webHistory);
  }

  Future<void> saveOperationHistory(List<OperationLogEntry> entries) async {
    _webHistory = List<OperationLogEntry>.from(entries);
  }

  Future<void> clearOperationHistory() async {
    _webHistory = [];
  }

  Future<AppCleanerSettings> loadSettings() async => _webSettings;

  Future<void> saveSettings(AppCleanerSettings settings) async {
    _webSettings = settings;
  }

  List<String> getBuiltInWhitelist() => const [
        'apple',
        'caches',
        'clouddocs',
        'containers',
        'dconf',
        'fontconfig',
        'gtk-3.0',
        'gtk-4.0',
        'icloud',
        'keyrings',
        'microsoft',
        'packages',
        'pipewire',
        'preferences',
        'systemd',
        'webkit',
        'windows',
      ];

  String getConfigDirectoryPath() =>
      '~/Library/Application Support/AppCleaner (Web Debug Mode)';
}
