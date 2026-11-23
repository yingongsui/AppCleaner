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
}
