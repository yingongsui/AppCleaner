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
    bool includeSampleLinuxPreview = false,
    DesktopPlatformType? filterPlatform,
  }) =>
      _backend.scanInstalledApps(
        includeSampleLinuxPreview: includeSampleLinuxPreview,
        filterPlatform: filterPlatform,
      );

  Future<void> ensureAppDataScanned(InstalledApp app) =>
      _backend.ensureAppDataScanned(app);

  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) =>
      _backend.scanOrphanedLeftovers(installedApps);

  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
  }) =>
      _backend.clearAppData(
        app: app,
        cacheOnly: cacheOnly,
        onlySelected: onlySelected,
        terminateIfRunning: terminateIfRunning,
      );

  Future<CleanActionResult> uninstallApp({
    required InstalledApp app,
    required bool removeSelectedData,
    required bool removeSelectedLinuxDeps,
    bool moveToTrashOnMac = true,
  }) =>
      _backend.uninstallApp(
        app: app,
        removeSelectedData: removeSelectedData,
        removeSelectedLinuxDeps: removeSelectedLinuxDeps,
        moveToTrashOnMac: moveToTrashOnMac,
      );

  Future<CleanActionResult> cleanOrphanLeftovers(
    List<OrphanLeftoverGroup> groups,
  ) =>
      _backend.cleanOrphanLeftovers(groups);

  Future<bool> terminateRunningApp(InstalledApp app) =>
      _backend.terminateRunningApp(app);

  Future<void> revealInFileManager(String path) =>
      _backend.revealInFileManager(path);
}
