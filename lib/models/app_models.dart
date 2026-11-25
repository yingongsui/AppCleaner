import 'package:flutter/foundation.dart';

/// Supported desktop platforms.
enum DesktopPlatformType {
  macos,
  linux,
  windows;

  static DesktopPlatformType get current {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return DesktopPlatformType.macos;
      case TargetPlatform.linux:
        return DesktopPlatformType.linux;
      case TargetPlatform.windows:
        return DesktopPlatformType.windows;
      default:
        return DesktopPlatformType.macos;
    }
  }

  String get label {
    switch (this) {
      case DesktopPlatformType.macos:
        return 'macOS';
      case DesktopPlatformType.linux:
        return 'Linux';
      case DesktopPlatformType.windows:
        return 'Windows';
    }
  }
}

/// Distinguishes user-installed applications from built-in / OS system apps.
enum AppOriginType {
  userInstalled,
  systemApp;

  String get label {
    switch (this) {
      case AppOriginType.userInstalled:
        return 'User App';
      case AppOriginType.systemApp:
        return 'System App';
    }
  }
}

/// How the application was installed on the system.
enum InstallSource {
  appBundle,
  homebrewCask,
  appStore,
  aptDpkg,
  pacman,
  dnfRpm,
  flatpak,
  snap,
  appImageOrOpt,
  win32Registry,
  msixAppx,
  systemBuiltIn;

  String get label {
    switch (this) {
      case InstallSource.appBundle:
        return 'macOS App (.app)';
      case InstallSource.homebrewCask:
        return 'Homebrew Cask';
      case InstallSource.appStore:
        return 'App Store';
      case InstallSource.aptDpkg:
        return 'APT / DEB Package';
      case InstallSource.pacman:
        return 'Pacman Package';
      case InstallSource.dnfRpm:
        return 'DNF / RPM Package';
      case InstallSource.flatpak:
        return 'Flatpak Sandbox';
      case InstallSource.snap:
        return 'Snap Container';
      case InstallSource.appImageOrOpt:
        return 'Local / Opt Binary';
      case InstallSource.win32Registry:
        return 'Win32 Installer';
      case InstallSource.msixAppx:
        return 'MSIX / Microsoft Store';
      case InstallSource.systemBuiltIn:
        return 'System Built-in';
    }
  }
}

/// Category of an application data, registry, or leftover item.
enum DataCategory {
  cache,
  preferences,
  appData,
  container,
  savedState,
  logs,
  launchAgent,
  registry;

  String get shortLabel {
    switch (this) {
      case DataCategory.cache:
        return 'Cache';
      case DataCategory.preferences:
        return 'Config';
      case DataCategory.appData:
        return 'App Data';
      case DataCategory.container:
        return 'Container';
      case DataCategory.savedState:
        return 'State';
      case DataCategory.logs:
        return 'Logs';
      case DataCategory.launchAgent:
        return 'Startup';
      case DataCategory.registry:
        return 'Registry';
    }
  }

  /// Whether this item belongs to "Clear Cache Only" (Android-style cache clear).
  bool get isCacheOnlyItem {
    return this == DataCategory.cache ||
        this == DataCategory.logs ||
        this == DataCategory.savedState;
  }
}

/// Represents a single directory, file, or Windows Registry key belonging to an app.
class AppDataItem {
  final String id;
  final String name;
  final String path;
  final DataCategory category;
  final int sizeBytes;
  final DateTime? lastModified;
  final bool isDirectory;
  final String description;
  bool selected;

  AppDataItem({
    required this.id,
    required this.name,
    required this.path,
    required this.category,
    required this.sizeBytes,
    this.lastModified,
    this.isDirectory = true,
    this.description = '',
    this.selected = true,
  });

  bool get isCacheLike => category.isCacheOnlyItem;

  bool get isRegistryKey =>
      category == DataCategory.registry ||
      path.startsWith(r'HKCU\') ||
      path.startsWith(r'HKLM\') ||
      path.startsWith(r'HKEY_');
}

/// Represents an additional library/dependency installed alongside a Linux package.
class LinuxDependencyPackage {
  final String packageName;
  final String version;
  final int sizeBytes;
  final String packageManager;
  final bool isAutoInstalled;
  final bool isExclusivelyRequired;
  final bool installedTogetherInHistory;
  final List<String> requiredByOthers;
  final String description;
  bool selected;

  LinuxDependencyPackage({
    required this.packageName,
    required this.version,
    required this.sizeBytes,
    required this.packageManager,
    required this.isAutoInstalled,
    required this.isExclusivelyRequired,
    this.installedTogetherInHistory = false,
    this.requiredByOthers = const [],
    this.description = '',
    bool? selected,
  }) : selected = selected ?? (isAutoInstalled && isExclusivelyRequired);

  bool get isSafeToRemove => isExclusivelyRequired && requiredByOthers.isEmpty;

  String get safetyBadgeText {
    if (isSafeToRemove && installedTogetherInHistory) {
      return 'Installed with app · Exclusive';
    }
    if (isSafeToRemove && isAutoInstalled) {
      return 'Auto-installed · Safe to remove';
    }
    if (requiredByOthers.isNotEmpty) {
      return 'Shared by ${requiredByOthers.take(2).join(", ")}';
    }
    return 'Optional dependency';
  }
}

/// Represents an installed application discovered on the system.
class InstalledApp {
  final String id;
  final String name;
  final String identifier;
  final String version;
  final String publisher;
  final String installPath;
  final String executablePath;
  final AppOriginType origin;
  final InstallSource installSource;
  final DesktopPlatformType platform;
  final int appSizeBytes;
  final String? linuxPackageName;
  final String? uninstallCommandHint;
  final DateTime? lastModified;
  final bool isSelfApp;
  Uint8List? iconBytes;
  bool isRunning;
  bool dataScanned;
  List<AppDataItem> dataItems;
  List<LinuxDependencyPackage> linuxDependencies;

  InstalledApp({
    required this.id,
    required this.name,
    required this.identifier,
    this.version = '',
    this.publisher = '',
    required this.installPath,
    this.executablePath = '',
    required this.origin,
    required this.installSource,
    required this.platform,
    this.appSizeBytes = 0,
    this.linuxPackageName,
    this.uninstallCommandHint,
    this.lastModified,
    this.isSelfApp = false,
    this.iconBytes,
    this.isRunning = false,
    this.dataScanned = false,
    List<AppDataItem>? dataItems,
    List<LinuxDependencyPackage>? linuxDependencies,
  })  : dataItems = dataItems ?? [],
        linuxDependencies = linuxDependencies ?? [];

  int get totalDataSizeBytes =>
      dataItems.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get cacheSizeBytes => dataItems
      .where((item) => item.isCacheLike)
      .fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get userDataSizeBytes => dataItems
      .where((item) => !item.isCacheLike)
      .fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get registryItemsCount =>
      dataItems.where((item) => item.isRegistryKey).length;

  int get selectedDataSizeBytes => dataItems
      .where((item) => item.selected)
      .fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get selectedLinuxDepsSizeBytes => linuxDependencies
      .where((dep) => dep.selected)
      .fold<int>(0, (sum, dep) => sum + dep.sizeBytes);

  int get totalFootprintBytes => appSizeBytes + totalDataSizeBytes;

  bool get isSystemApp => origin == AppOriginType.systemApp;

  /// Protected from uninstallation (either OS system app or AppCleaner itself).
  bool get isProtectedFromUninstall => isSystemApp || isSelfApp;
}

/// Represents a group of orphaned leftover files/registry keys belonging to a previously uninstalled app.
class OrphanLeftoverGroup {
  final String id;
  final String suspectedAppName;
  final String identifier;
  final DesktopPlatformType platform;
  final String confidenceReason;
  final List<AppDataItem> items;

  OrphanLeftoverGroup({
    required this.id,
    required this.suspectedAppName,
    required this.identifier,
    required this.platform,
    required this.confidenceReason,
    required this.items,
  });

  int get totalSizeBytes =>
      items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get selectedSizeBytes => items
      .where((item) => item.selected)
      .fold<int>(0, (sum, item) => sum + item.sizeBytes);

  int get selectedCount => items.where((item) => item.selected).length;

  bool get allSelected => items.isNotEmpty && items.every((i) => i.selected);

  bool get anySelected => items.any((i) => i.selected);
}

/// Result of a data clear, leftover cleanup, or app uninstall operation.
class CleanActionResult {
  final bool success;
  final int deletedCount;
  final int freedBytes;
  final List<String> deletedPaths;
  final List<String> failedPaths;
  final List<String> removedPackages;
  final List<String> commandLogs;
  final String summaryMessage;

  const CleanActionResult({
    required this.success,
    required this.deletedCount,
    required this.freedBytes,
    this.deletedPaths = const [],
    this.failedPaths = const [],
    this.removedPackages = const [],
    this.commandLogs = const [],
    required this.summaryMessage,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'deletedCount': deletedCount,
        'freedBytes': freedBytes,
        'deletedPaths': deletedPaths,
        'failedPaths': failedPaths,
        'removedPackages': removedPackages,
        'commandLogs': commandLogs,
        'summaryMessage': summaryMessage,
      };

  factory CleanActionResult.fromJson(Map<String, dynamic> json) {
    return CleanActionResult(
      success: json['success'] == true,
      deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
      freedBytes: (json['freedBytes'] as num?)?.toInt() ?? 0,
      deletedPaths: (json['deletedPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      failedPaths: (json['failedPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      removedPackages: (json['removedPackages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      commandLogs: (json['commandLogs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      summaryMessage: json['summaryMessage']?.toString() ?? '',
    );
  }
}

/// Persistent history entry for a cleaning, reset, or uninstallation action.
class OperationLogEntry {
  final DateTime timestamp;
  final String title;
  final CleanActionResult result;

  const OperationLogEntry({
    required this.timestamp,
    required this.title,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'result': result.toJson(),
      };

  factory OperationLogEntry.fromJson(Map<String, dynamic> json) {
    return OperationLogEntry(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      title: json['title']?.toString() ?? 'Operation',
      result: CleanActionResult.fromJson(
        (json['result'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// User-defined mapping associating a leftover directory, file, or Registry key
/// with a specific installed application.
class CustomAppAssociation {
  final String path;
  final String label;
  final DataCategory category;
  final String appId;
  final String appIdentifier;
  final String appName;

  const CustomAppAssociation({
    required this.path,
    required this.label,
    required this.category,
    required this.appId,
    required this.appIdentifier,
    required this.appName,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'label': label,
        'category': category.name,
        'appId': appId,
        'appIdentifier': appIdentifier,
        'appName': appName,
      };

  factory CustomAppAssociation.fromJson(Map<String, dynamic> json) {
    final catName = json['category']?.toString() ?? '';
    final cat = DataCategory.values.firstWhere(
      (c) => c.name == catName,
      orElse: () => DataCategory.appData,
    );
    return CustomAppAssociation(
      path: json['path']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      category: cat,
      appId: json['appId']?.toString() ?? '',
      appIdentifier: json['appIdentifier']?.toString() ?? '',
      appName: json['appName']?.toString() ?? '',
    );
  }
}

/// Persistent user preferences, custom whitelist rules, and manual app associations.
class AppCleanerSettings {
  /// Inspect 1-level subfolders inside company/vendor folders
  /// (e.g. `Softdeluxe/Free Download Manager` or `Google/Chrome`).
  final bool scanVendorSubfolders;

  /// Default deletion mode in confirmation dialogs (`true` = Move to System Trash).
  final bool defaultMoveToTrash;

  /// Automatically start scanning Orphaned Leftovers when opening the tab if empty.
  final bool autoScanOrphansOnOpen;

  /// Expand Orphaned Leftover group cards by default (`false` = collapsed by default).
  final bool expandOrphanCardsByDefault;

  /// Include System Apps in the initial Installed Apps filter on launch.
  final bool includeSystemAppsByDefault;

  /// User-defined whitelist rules (exact paths or case-insensitive folder/identifier names).
  final List<String> customWhitelist;

  /// User-defined manual associations linking leftover paths to installed apps.
  final List<CustomAppAssociation> customAssociations;

  const AppCleanerSettings({
    this.scanVendorSubfolders = true,
    this.defaultMoveToTrash = true,
    this.autoScanOrphansOnOpen = true,
    this.expandOrphanCardsByDefault = false,
    this.includeSystemAppsByDefault = false,
    this.customWhitelist = const [],
    this.customAssociations = const [],
  });

  AppCleanerSettings copyWith({
    bool? scanVendorSubfolders,
    bool? defaultMoveToTrash,
    bool? autoScanOrphansOnOpen,
    bool? expandOrphanCardsByDefault,
    bool? includeSystemAppsByDefault,
    List<String>? customWhitelist,
    List<CustomAppAssociation>? customAssociations,
  }) {
    return AppCleanerSettings(
      scanVendorSubfolders: scanVendorSubfolders ?? this.scanVendorSubfolders,
      defaultMoveToTrash: defaultMoveToTrash ?? this.defaultMoveToTrash,
      autoScanOrphansOnOpen:
          autoScanOrphansOnOpen ?? this.autoScanOrphansOnOpen,
      expandOrphanCardsByDefault:
          expandOrphanCardsByDefault ?? this.expandOrphanCardsByDefault,
      includeSystemAppsByDefault:
          includeSystemAppsByDefault ?? this.includeSystemAppsByDefault,
      customWhitelist: customWhitelist ?? this.customWhitelist,
      customAssociations: customAssociations ?? this.customAssociations,
    );
  }

  /// Checks whether [path], [name], or [identifier] matches any custom whitelist rule.
  bool isWhitelisted(
    String path, {
    String? name,
    String? identifier,
  }) {
    if (customWhitelist.isEmpty) return false;
    final normPath = path.trim().replaceAll(r'\', '/').toLowerCase();
    final pathBase = normPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
    final normName = name?.trim().toLowerCase() ?? '';
    final normId = identifier?.trim().toLowerCase() ?? '';

    for (final rawRule in customWhitelist) {
      final rule = rawRule.trim().replaceAll(r'\', '/').toLowerCase();
      if (rule.isEmpty) continue;
      if (normPath == rule ||
          (normPath.isNotEmpty && normPath.startsWith('$rule/')) ||
          pathBase == rule ||
          (normName.isNotEmpty && normName == rule) ||
          (normId.isNotEmpty && normId == rule)) {
        return true;
      }
    }
    return false;
  }

  /// Returns all manual associations targeting [app].
  List<CustomAppAssociation> associationsForApp(InstalledApp app) {
    if (customAssociations.isEmpty) return const [];
    final appIdLower = app.identifier.trim().toLowerCase();
    final appNameLower = app.name.trim().toLowerCase();
    return customAssociations.where((a) {
      if (a.appId == app.id) return true;
      if (appIdLower.isNotEmpty &&
          a.appIdentifier.trim().toLowerCase() == appIdLower) {
        return true;
      }
      return a.appName.trim().toLowerCase() == appNameLower;
    }).toList();
  }

  /// Returns `true` if [path] is manually associated with an app that is
  /// currently present in [installedApps].
  bool isAssociatedWithInstalledApp(
    String path,
    List<InstalledApp> installedApps,
  ) {
    if (customAssociations.isEmpty) return false;
    final normPath = path.trim().replaceAll(r'\', '/').toLowerCase();
    for (final assoc in customAssociations) {
      final assocPath = assoc.path.trim().replaceAll(r'\', '/').toLowerCase();
      if (assocPath.isEmpty) continue;
      final pathMatches = normPath == assocPath ||
          normPath.startsWith('$assocPath/') ||
          assocPath.startsWith('$normPath/');
      if (!pathMatches) continue;

      final appStillInstalled = installedApps.any(
        (app) =>
            app.id == assoc.appId ||
            (app.identifier.isNotEmpty &&
                app.identifier.toLowerCase() ==
                    assoc.appIdentifier.toLowerCase()) ||
            app.name.toLowerCase() == assoc.appName.toLowerCase(),
      );
      if (appStillInstalled) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'scanVendorSubfolders': scanVendorSubfolders,
        'defaultMoveToTrash': defaultMoveToTrash,
        'autoScanOrphansOnOpen': autoScanOrphansOnOpen,
        'expandOrphanCardsByDefault': expandOrphanCardsByDefault,
        'includeSystemAppsByDefault': includeSystemAppsByDefault,
        'customWhitelist': customWhitelist,
        'customAssociations':
            customAssociations.map((a) => a.toJson()).toList(),
      };

  factory AppCleanerSettings.fromJson(Map<String, dynamic> json) {
    return AppCleanerSettings(
      scanVendorSubfolders: json['scanVendorSubfolders'] != false,
      defaultMoveToTrash: json['defaultMoveToTrash'] != false,
      autoScanOrphansOnOpen: json['autoScanOrphansOnOpen'] != false,
      expandOrphanCardsByDefault: json['expandOrphanCardsByDefault'] == true,
      includeSystemAppsByDefault: json['includeSystemAppsByDefault'] == true,
      customWhitelist: (json['customWhitelist'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          const [],
      customAssociations: (json['customAssociations'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (m) => CustomAppAssociation.fromJson(
                  m.cast<String, dynamic>(),
                ),
              )
              .where((a) => a.path.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}
