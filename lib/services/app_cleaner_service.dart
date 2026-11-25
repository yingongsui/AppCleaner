import '../models/app_models.dart';
import 'app_cleaner_backend_io.dart'
    if (dart.library.js_interop) 'app_cleaner_backend_stub.dart';

/// Unified cross-platform service for scanning apps, inspecting app data/cache,
/// clearing app data (Android-style reset without uninstalling), uninstalling apps
/// along with leftovers and Linux auto-installed dependency libraries, and cleaning
/// orphaned leftovers.
///
/// Automatically uses native `dart:io` scanners on macOS/Linux/Windows and
/// switches to an interactive multi-platform UI debug simulator on Flutter Web.
class AppCleanerService {
  final AppCleanerPlatformBackend _backend;

  AppCleanerService({AppCleanerPlatformBackend? backend})
      : _backend = backend ?? AppCleanerPlatformBackend();

  Future<List<InstalledApp>> scanInstalledApps({
    DesktopPlatformType? filterPlatform,
  }) =>
      _backend.scanInstalledApps(
        filterPlatform: filterPlatform,
      );

  Future<void> ensureAppDataScanned(
    InstalledApp app, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) =>
      _backend.ensureAppDataScanned(app, settings: settings);

  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) =>
      _backend.scanOrphanedLeftovers(installedApps, settings: settings);

  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
    bool moveToTrash = true,
  }) =>
      _backend.clearAppData(
        app: app,
        cacheOnly: cacheOnly,
        onlySelected: onlySelected,
        terminateIfRunning: terminateIfRunning,
        moveToTrash: moveToTrash,
      );

  Future<CleanActionResult> uninstallApp({
    required InstalledApp app,
    required bool removeSelectedData,
    required bool removeSelectedLinuxDeps,
    bool moveToTrash = true,
  }) =>
      _backend.uninstallApp(
        app: app,
        removeSelectedData: removeSelectedData,
        removeSelectedLinuxDeps: removeSelectedLinuxDeps,
        moveToTrash: moveToTrash,
      );

  Future<CleanActionResult> cleanOrphanLeftovers(
    List<OrphanLeftoverGroup> groups, {
    bool moveToTrash = true,
  }) =>
      _backend.cleanOrphanLeftovers(
        groups,
        moveToTrash: moveToTrash,
      );

  Future<bool> terminateRunningApp(InstalledApp app) =>
      _backend.terminateRunningApp(app);

  Future<void> revealInFileManager(String path) =>
      _backend.revealInFileManager(path);

  Future<List<OperationLogEntry>> loadOperationHistory() =>
      _backend.loadOperationHistory();

  Future<void> saveOperationHistory(List<OperationLogEntry> entries) =>
      _backend.saveOperationHistory(entries);

  Future<void> clearOperationHistory() => _backend.clearOperationHistory();

  Future<AppCleanerSettings> loadSettings() => _backend.loadSettings();

  Future<void> saveSettings(AppCleanerSettings settings) =>
      _backend.saveSettings(settings);

  List<String> getBuiltInWhitelist() => _backend.getBuiltInWhitelist();

  String getConfigDirectoryPath() => _backend.getConfigDirectoryPath();
}
