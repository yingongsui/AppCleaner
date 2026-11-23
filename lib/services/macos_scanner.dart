import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/io_file_utils.dart';
import '../utils/platform_parsers.dart';
import 'macos_native_icons.dart';

/// Scans macOS applications (.app bundles), distinguishes User Apps vs System Apps,
/// discovers associated data/cache/containers in ~/Library, and detects orphaned leftovers.
class MacOsAppScanner {
  String get _homeDir => Platform.environment['HOME'] ?? '/Users/Shared';

  static const Set<String> _appleSystemBundleIds = {
    'com.apple.Safari',
    'com.apple.mail',
    'com.apple.AddressBook',
    'com.apple.iCal',
    'com.apple.Reminders',
    'com.apple.Notes',
    'com.apple.Maps',
    'com.apple.Photos',
    'com.apple.Music',
    'com.apple.TV',
    'com.apple.podcasts',
    'com.apple.news',
    'com.apple.stocks',
    'com.apple.Home',
    'com.apple.VoiceMemos',
    'com.apple.FaceTime',
    'com.apple.MobileSMS',
    'com.apple.AppStore',
    'com.apple.systempreferences',
    'com.apple.Preview',
    'com.apple.TextEdit',
    'com.apple.QuickTimePlayerX',
    'com.apple.calculator',
    'com.apple.Dictionary',
    'com.apple.FontBook',
    'com.apple.Image_Capture',
    'com.apple.launchpad.launcher',
    'com.apple.MissionControl',
    'com.apple.Siri',
    'com.apple.TimeMachine',
    'com.apple.ActivityMonitor',
    'com.apple.Terminal',
    'com.apple.Console',
    'com.apple.DiskUtility',
    'com.apple.KeychainAccess',
    'com.apple.SystemProfiler',
    'com.apple.Screenshot',
    'com.apple.ScriptEditor2',
    'com.apple.audio.AudioMIDISetup',
    'com.apple.BluetoothFileExchange',
    'com.apple.ColorSyncUtility',
    'com.apple.DigitalColorMeter',
    'com.apple.Grapher',
    'com.apple.MigrateAssistant',
    'com.apple.VoiceOverUtility',
    'com.apple.AirPortBaseStationAgent',
    'com.apple.print.PrinterProxy',
    'com.apple.Passwords',
    'com.apple.weather',
    'com.apple.clock',
    'com.apple.freeform',
    'com.apple.findmy',
    'com.apple.shortcuts',
    'com.apple.tips',
    'com.apple.Stickies',
    'com.apple.Chess',
    'com.apple.PhotoBooth',
    'com.apple.Automator',
  };

  static const Set<String> _ignoredOrphanNames = {
    'apple',
    'Caches',
    'CloudDocs',
    'com.apple',
    'Knowledge',
    'Metadata',
    'Mobile Documents',
    'Preferences',
    'Saved Application State',
    'SyncedPreferences',
    'WebKit',
    'HTTPStorages',
    'Cookies',
    'Containers',
    'Group Containers',
    'Application Support',
    'LaunchAgents',
    'Logs',
    'AddressBook',
    'Assistants',
    'Audio',
    'Autosave Information',
    'Accounts',
    'Calendars',
    'CallServices',
    'ColorPickers',
    'Colors',
    'Compositions',
    'ConfigurationProfiles',
    'Contacts',
    'CoreData',
    'CoreFollowUp',
    'Daemon Containers',
    'DataDeliveryServices',
    'Developer',
    'Dictionaries',
    'DirectoryServices',
    'DisplayServices',
    'DoNotDisturb',
    'Favorites',
    'FileProvider',
    'Finance',
    'FontCollections',
    'Fonts',
    'FrontBoard',
    'GameKit',
    'GeoServices',
    'HomeKit',
    'IdentityServices',
    'Input Methods',
    'Internet Plug-Ins',
    'Keyboard',
    'Keyboard Layouts',
    'KeyboardServices',
    'Keychains',
    'LanguageModeling',
    'LaunchDaemons',
    'LocationBundles',
    'Mail',
    'Maps',
    'MediaStream',
    'Messages',
    'News',
    'Notes',
    'Passes',
    'PDF Services',
    'PersonalizationPortrait',
    'Personas',
    'Photos',
    'PreferencePanes',
    'Printers',
    'QuickLook',
    'Receipts',
    'Reminders',
    'ResponseKit',
    'Safari',
    'SafariSafeBrowsing',
    'Screen Savers',
    'ScreenRecordings',
    'Scripts',
    'Security',
    'Services',
    'Sharing',
    'Shortcuts',
    'Siri',
    'Sounds',
    'Speech',
    'Spelling',
    'Spotlight',
    'Staging',
    'StatusKit',
    'Suggestions',
    'SystemConfiguration',
    'Trial',
    'Translation',
    'Updates',
    'UserNotifications',
    'Video',
    'VoiceTrigger',
    'Voices',
    'Weather',
    'Workflows',
    'CrashReporter',
    'DiagnosticReports',
    'Homebrew',
    'pip',
    'npm',
    'yarn',
    'pnpm',
    'cargo',
    'rustup',
    'go-build',
    'flutter',
    'dart',
    'pub',
    'gradle',
    'maven',
    'cocoapods',
    'Google',
    'Microsoft',
    'JetBrains',
    'Mozilla',
  };

  /// Scans all installed macOS applications.
  Future<List<InstalledApp>> scanInstalledApps() async {
    final searchRoots = <({String path, bool forceSystem})>[
      (path: '/Applications', forceSystem: false),
      (path: '/Applications/Utilities', forceSystem: false),
      (path: '$_homeDir/Applications', forceSystem: false),
      (path: '/System/Applications', forceSystem: true),
      (path: '/System/Applications/Utilities', forceSystem: true),
    ];

    final caskNames = await _discoverHomebrewCasks();
    final runningProcesses = await _fetchRunningProcessSnapshot();

    final seenPaths = <String>{};
    final candidates = <({String path, bool forceSystem})>[];

    for (final root in searchRoots) {
      final dir = Directory(root.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entities = [];
      try {
        entities = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entity in entities) {
        final path = entity.path;
        if (!path.toLowerCase().endsWith('.app')) continue;
        if (!seenPaths.add(path)) continue;

        try {
          final resolved = await entity.resolveSymbolicLinks();
          if (resolved != path && seenPaths.contains(resolved)) {
            continue;
          }
          seenPaths.add(resolved);
        } catch (_) {}

        candidates.add((path: path, forceSystem: root.forceSystem));
      }
    }

    // Inspect app bundles concurrently in bounded batches for fast startup scanning
    final seenBundleIds = <String>{};
    final apps = <InstalledApp>[];
    const batchSize = 8;

    for (var i = 0; i < candidates.length; i += batchSize) {
      final chunk = candidates.sublist(
        i,
        (i + batchSize).clamp(0, candidates.length),
      );
      final inspected = await Future.wait(
        chunk.map(
          (c) => _inspectAppBundle(
            appPath: c.path,
            forceSystem: c.forceSystem,
            caskTokens: caskNames,
            runningProcessOutput: runningProcesses,
          ),
        ),
      );

      for (final app in inspected) {
        if (app == null) continue;
        if (app.identifier.isNotEmpty && !seenBundleIds.add(app.identifier)) {
          continue;
        }
        apps.add(app);
      }
    }

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  Future<InstalledApp?> _inspectAppBundle({
    required String appPath,
    required bool forceSystem,
    required Set<String> caskTokens,
    required String runningProcessOutput,
  }) async {
    final infoPlistPath = '$appPath/Contents/Info.plist';
    final plistFile = File(infoPlistPath);
    Map<String, String> plistData = {};
    if (await plistFile.exists()) {
      plistData = await _parseInfoPlist(plistFile);
    }

    final rawBundleName = FormatUtils.basename(appPath);
    final fallbackName = rawBundleName.endsWith('.app')
        ? rawBundleName.substring(0, rawBundleName.length - 4)
        : rawBundleName;

    final displayName = (plistData['CFBundleDisplayName']?.isNotEmpty == true)
        ? plistData['CFBundleDisplayName']!
        : (plistData['CFBundleName']?.isNotEmpty == true
            ? plistData['CFBundleName']!
            : fallbackName);

    final bundleId = plistData['CFBundleIdentifier'] ??
        'macos.app.${FormatUtils.normalizeToken(fallbackName)}';
    final version = plistData['CFBundleShortVersionString'] ??
        plistData['CFBundleVersion'] ??
        '';
    final executableName = plistData['CFBundleExecutable'] ?? fallbackName;
    final executablePath = '$appPath/Contents/MacOS/$executableName';

    final isSystem = forceSystem ||
        appPath.startsWith('/System/') ||
        _appleSystemBundleIds.contains(bundleId) ||
        (bundleId.startsWith('com.apple.') &&
            appPath.startsWith('/Applications/Utilities'));

    InstallSource installSource = InstallSource.appBundle;
    if (isSystem) {
      installSource = InstallSource.systemBuiltIn;
    } else if (await Directory('$appPath/Contents/_MASReceipt').exists()) {
      installSource = InstallSource.appStore;
    } else {
      final normName = FormatUtils.normalizeToken(fallbackName);
      if (caskTokens.contains(normName)) {
        installSource = InstallSource.homebrewCask;
      }
    }

    String publisher = '';
    final idParts = bundleId.split('.');
    if (idParts.length >= 2) {
      publisher = idParts[1];
      if (publisher == 'apple') {
        publisher = 'Apple Inc.';
      } else if (publisher.isNotEmpty) {
        publisher = publisher[0].toUpperCase() + publisher.substring(1);
      }
    }

    final isSelf = IoFileUtils.isSelfApplication(
      installPath: appPath,
      identifier: bundleId,
      name: displayName,
      executablePath: executablePath,
    );

    final modified = await IoFileUtils.getLastModified(appPath);
    final isRunning = isSelf ||
        runningProcessOutput.contains(appPath) ||
        (executableName.length > 3 &&
            runningProcessOutput.contains('/MacOS/$executableName'));

    final appSize = await IoFileUtils.calculateEntitySize(
      appPath,
      maxFiles: 2200,
    );
    final iconBytes = isSelf
        ? null
        : await MacOsNativeIconBridge.getAppIconPng(appPath);

    return InstalledApp(
      id: bundleId.isNotEmpty ? '$bundleId@$appPath' : appPath,
      name: displayName,
      identifier: bundleId,
      version: version,
      publisher: publisher,
      installPath: appPath,
      executablePath: executablePath,
      origin: isSystem ? AppOriginType.systemApp : AppOriginType.userInstalled,
      installSource: installSource,
      platform: DesktopPlatformType.macos,
      appSizeBytes: appSize,
      lastModified: modified,
      isSelfApp: isSelf,
      iconBytes: iconBytes,
      isRunning: isRunning,
    );
  }

  Future<Map<String, String>> _parseInfoPlist(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length >= 8) {
        final header = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
        if (header == 'bplist') {
          final res = await Process.run(
            'plutil',
            ['-convert', 'json', '-o', '-', file.path],
          );
          if (res.exitCode == 0) {
            final decoded = jsonDecode(res.stdout as String);
            if (decoded is Map) {
              return decoded.map(
                (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
              );
            }
          }
          return {};
        }
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      return PlatformParsers.parseXmlPlist(content);
    } catch (_) {
      return {};
    }
  }

  /// Scans all data, cache, config, containers, and launch agents associated with [app].
  Future<List<AppDataItem>> scanAppDataItems(InstalledApp app) async {
    final libraryDir = '$_homeDir/Library';
    final bundleId = app.identifier.trim();
    final bundleIdLower = bundleId.toLowerCase();

    final rawBundleFile = FormatUtils.basename(app.installPath);
    final rawAppFolderName = rawBundleFile.endsWith('.app')
        ? rawBundleFile.substring(0, rawBundleFile.length - 4)
        : rawBundleFile;
    final exeBaseName = FormatUtils.basename(app.executablePath);
    final bundleParts = bundleId.split('.');
    final bundleLastSegment =
        bundleParts.length >= 3 ? bundleParts.last.trim() : '';
    final bundleVendorSegment =
        bundleParts.length >= 2 ? bundleParts[1].trim() : '';

    // Exclude overly generic executable names (like 'Electron' or 'applet') from name matching.
    const genericExeNames = {
      'electron',
      'applet',
      'launcher',
      'runner',
      'helper',
      'java',
      'python',
      'python3',
      'node',
      'main',
    };

    final nameTokens = <String>{
      if (app.name.trim().length >= 3) app.name.trim(),
      if (rawAppFolderName.trim().length >= 3) rawAppFolderName.trim(),
      if (exeBaseName.trim().length >= 3 &&
          !genericExeNames.contains(exeBaseName.toLowerCase()))
        exeBaseName.trim(),
      if (bundleLastSegment.length >= 4 &&
          !genericExeNames.contains(bundleLastSegment.toLowerCase()))
        bundleLastSegment,
    };
    final normalizedNameTokens = nameTokens
        .map(FormatUtils.normalizeToken)
        .where((t) => t.length >= 3)
        .toSet();

    final searchTargets = <({
      String dirPath,
      DataCategory category,
      String description,
      bool matchByName,
      bool matchByGroupSuffix,
      bool scanVendorSubdir,
    })>[
      (
        dirPath: '$libraryDir/Application Support',
        category: DataCategory.appData,
        description: 'Application core data & user profile directory',
        matchByName: true,
        matchByGroupSuffix: false,
        scanVendorSubdir: true,
      ),
      (
        dirPath: '$libraryDir/Caches',
        category: DataCategory.cache,
        description: 'Application runtime cache & offline assets',
        matchByName: true,
        matchByGroupSuffix: false,
        scanVendorSubdir: true,
      ),
      (
        dirPath: '$libraryDir/Preferences',
        category: DataCategory.preferences,
        description: 'User preference property list (.plist)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Preferences/ByHost',
        category: DataCategory.preferences,
        description: 'Host-specific preference property list (.plist)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/SyncedPreferences',
        category: DataCategory.preferences,
        description: 'Synced preference property list (.plist)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Containers',
        category: DataCategory.container,
        description: 'macOS App Sandbox container directory',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Group Containers',
        category: DataCategory.container,
        description: 'Shared application group sandbox container',
        matchByName: false,
        matchByGroupSuffix: true,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Application Scripts',
        category: DataCategory.appData,
        description: 'Sandboxed application scripts directory',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Saved Application State',
        category: DataCategory.savedState,
        description: 'Saved window geometry & restoration state',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Logs',
        category: DataCategory.logs,
        description: 'Application runtime & diagnostic logs',
        matchByName: true,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/Cookies',
        category: DataCategory.savedState,
        description: 'HTTP network cookie storage',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/WebKit',
        category: DataCategory.cache,
        description: 'WebKit web storage & IndexedDB cache',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/HTTPStorages',
        category: DataCategory.savedState,
        description: 'HTTP session & credential storage',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '$libraryDir/LaunchAgents',
        category: DataCategory.launchAgent,
        description: 'User login background service (LaunchAgent)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      // Cross-platform XDG config directory used by many macOS ports & Electron/Qt apps
      (
        dirPath: '$_homeDir/.config',
        category: DataCategory.preferences,
        description: 'XDG configuration directory (~/.config)',
        matchByName: true,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      // System-wide machine-level preferences & support files
      (
        dirPath: '/Library/Preferences',
        category: DataCategory.preferences,
        description: 'System-wide preference property list (/Library/Preferences)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '/Library/Application Support',
        category: DataCategory.appData,
        description: 'System-wide application support (/Library/Application Support)',
        matchByName: true,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
      (
        dirPath: '/Library/LaunchAgents',
        category: DataCategory.launchAgent,
        description: 'System-wide login agent (/Library/LaunchAgents)',
        matchByName: false,
        matchByGroupSuffix: false,
        scanVendorSubdir: false,
      ),
    ];

    final foundPaths = <String>{};
    final items = <AppDataItem>[];
    final bundlePrefix2 = bundleParts.length >= 2
        ? '${bundleParts[0].toLowerCase()}.${bundleParts[1].toLowerCase()}'
        : '';

    Future<void> addMatchedEntry(
      String entryPath,
      DataCategory category,
      String description,
    ) async {
      if (!foundPaths.add(entryPath)) return;
      final size = await IoFileUtils.calculateEntitySize(
        entryPath,
        maxFiles: 3000,
      );
      final modified = await IoFileUtils.getLastModified(entryPath);
      final stat = await FileStat.stat(entryPath);
      items.add(
        AppDataItem(
          id: entryPath,
          name: FormatUtils.basename(entryPath),
          path: entryPath,
          category: category,
          sizeBytes: size,
          lastModified: modified,
          isDirectory: stat.type == FileSystemEntityType.directory,
          description: description,
          selected: true,
        ),
      );
    }

    for (final target in searchTargets) {
      final dir = Directory(target.dirPath);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        final baseLower = base.toLowerCase();

        bool matched = false;

        if (bundleIdLower.isNotEmpty &&
            !bundleIdLower.startsWith('macos.app.')) {
          if (baseLower == bundleIdLower ||
              baseLower == '$bundleIdLower.plist' ||
              baseLower == '$bundleIdLower.savedstate' ||
              baseLower == '$bundleIdLower.binarycookies' ||
              baseLower.startsWith('$bundleIdLower.')) {
            matched = true;
          } else if (target.matchByGroupSuffix &&
              (baseLower.contains(bundleIdLower) ||
                  (bundlePrefix2.length >= 8 &&
                      bundleLastSegment.length >= 4 &&
                      baseLower.contains(bundlePrefix2) &&
                      baseLower.contains(bundleLastSegment.toLowerCase())))) {
            matched = true;
          }
        }

        if (!matched && target.matchByName) {
          final normBase = FormatUtils.normalizeToken(base);
          if (normBase.length >= 3 &&
              normalizedNameTokens.contains(normBase)) {
            matched = true;
          }
        }

        if (matched) {
          await addMatchedEntry(
            entry.path,
            target.category,
            target.description,
          );
          continue;
        }

        // Check nested <Vendor>/<App> folders (e.g. Application Support/Google/Chrome)
        if (target.scanVendorSubdir &&
            entry is Directory &&
            bundleVendorSegment.length >= 3 &&
            FormatUtils.normalizeToken(base) ==
                FormatUtils.normalizeToken(bundleVendorSegment)) {
          try {
            await for (final child in entry.list(followLinks: false)) {
              final childBase = FormatUtils.basename(child.path);
              final childNorm = FormatUtils.normalizeToken(childBase);
              if (childNorm.length >= 3 &&
                  normalizedNameTokens.contains(childNorm)) {
                await addMatchedEntry(
                  child.path,
                  target.category,
                  '${target.description} ($base/$childBase)',
                );
              }
            }
          } catch (_) {}
        }
      }
    }

    // Check hidden dot-directory directly in HOME (e.g. ~/.vscode, ~/.0ad)
    for (final token in normalizedNameTokens) {
      if (token.length < 4) continue;
      final dotPath = '$_homeDir/.$token';
      if (await Directory(dotPath).exists()) {
        await addMatchedEntry(
          dotPath,
          DataCategory.preferences,
          'User home hidden config directory (~/.$token)',
        );
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  /// Scans `~/Library` for orphaned leftover files belonging to uninstalled applications.
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) async {
    final libraryDir = '$_homeDir/Library';

    final installedBundleIds = <String>{};
    final installedBundlePrefixes = <String>{};
    final installedNormalizedNames = <String>{};

    for (final app in installedApps) {
      final bid = app.identifier.toLowerCase().trim();
      if (bid.isNotEmpty) {
        installedBundleIds.add(bid);
        final parts = bid.split('.');
        if (parts.length >= 3) {
          installedBundlePrefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
        if (parts.length >= 2) {
          installedNormalizedNames.add(FormatUtils.normalizeToken(parts.last));
        }
      }
      final normName = FormatUtils.normalizeToken(app.name);
      if (normName.length >= 2) {
        installedNormalizedNames.add(normName);
      }
      final rawFile = FormatUtils.basename(app.installPath);
      final rawFolder = rawFile.endsWith('.app')
          ? rawFile.substring(0, rawFile.length - 4)
          : rawFile;
      final normFolder = FormatUtils.normalizeToken(rawFolder);
      if (normFolder.length >= 2) {
        installedNormalizedNames.add(normFolder);
      }
    }

    final scanDirs = <({
      String path,
      DataCategory category,
      bool requireBundleIdFormat,
    })>[
      (
        path: '$libraryDir/Application Support',
        category: DataCategory.appData,
        requireBundleIdFormat: false,
      ),
      (
        path: '$libraryDir/Caches',
        category: DataCategory.cache,
        requireBundleIdFormat: true,
      ),
      (
        path: '$libraryDir/Containers',
        category: DataCategory.container,
        requireBundleIdFormat: true,
      ),
      (
        path: '$libraryDir/Saved Application State',
        category: DataCategory.savedState,
        requireBundleIdFormat: true,
      ),
      (
        path: '$libraryDir/Preferences',
        category: DataCategory.preferences,
        requireBundleIdFormat: true,
      ),
      (
        path: '$libraryDir/HTTPStorages',
        category: DataCategory.savedState,
        requireBundleIdFormat: true,
      ),
      (
        path: '$libraryDir/LaunchAgents',
        category: DataCategory.launchAgent,
        requireBundleIdFormat: true,
      ),
    ];

    final groupedItems = <String, List<AppDataItem>>{};
    final groupTitles = <String, String>{};

    final bundleRegex = RegExp(
      r'^(com|org|io|net|app|dev|me|co|us|de|jp|cn|uk|fr|ru|ch|nl|se|tv|ai)\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_.-]+$',
    );

    for (final scanDir in scanDirs) {
      final dir = Directory(scanDir.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        if (base.startsWith('.') || _ignoredOrphanNames.contains(base)) {
          continue;
        }

        String cleanId = base;
        for (final ext in ['.savedState', '.plist', '.binarycookies']) {
          if (cleanId.endsWith(ext)) {
            cleanId = cleanId.substring(0, cleanId.length - ext.length);
          }
        }

        final cleanLower = cleanId.toLowerCase();
        if (cleanLower.startsWith('com.apple.') ||
            cleanLower.startsWith('group.com.apple.') ||
            cleanLower.startsWith('system.') ||
            cleanLower.contains('app_cleaner') ||
            cleanLower.contains('appcleaner')) {
          continue;
        }

        final looksLikeBundleId = bundleRegex.hasMatch(cleanId);
        if (scanDir.requireBundleIdFormat && !looksLikeBundleId) {
          continue;
        }

        bool belongsToInstalled = false;
        if (installedBundleIds.contains(cleanLower)) {
          belongsToInstalled = true;
        } else {
          for (final bid in installedBundleIds) {
            if (cleanLower.startsWith('$bid.') ||
                bid.startsWith('$cleanLower.')) {
              belongsToInstalled = true;
              break;
            }
          }
        }

        if (!belongsToInstalled && looksLikeBundleId) {
          final parts = cleanLower.split('.');
          if (parts.length >= 3) {
            final prefix3 = '${parts[0]}.${parts[1]}.${parts[2]}';
            if (installedBundlePrefixes.contains(prefix3)) {
              belongsToInstalled = true;
            }
          }
          final lastToken = FormatUtils.normalizeToken(parts.last);
          if (lastToken.length >= 4 &&
              installedNormalizedNames.contains(lastToken)) {
            belongsToInstalled = true;
          }
        }

        if (!belongsToInstalled && !looksLikeBundleId) {
          final norm = FormatUtils.normalizeToken(cleanId);
          if (norm.length < 3 ||
              installedNormalizedNames.contains(norm) ||
              _ignoredOrphanNames.any((ig) => ig.toLowerCase() == cleanLower)) {
            belongsToInstalled = true;
          }
        }

        if (belongsToInstalled) continue;

        final size = await IoFileUtils.calculateEntitySize(
          entry.path,
          maxFiles: 1500,
        );
        if (size == 0) continue;

        final modified = await IoFileUtils.getLastModified(entry.path);
        final stat = await FileStat.stat(entry.path);

        String groupKey = cleanLower;
        String displayName = cleanId;
        if (looksLikeBundleId) {
          final parts = cleanId.split('.');
          if (parts.length >= 3) {
            groupKey =
                '${parts[0].toLowerCase()}.${parts[1].toLowerCase()}.${parts[2].toLowerCase()}';
            displayName = _humanizeBundleId(cleanId);
          }
        }

        groupTitles.putIfAbsent(groupKey, () => displayName);
        groupedItems.putIfAbsent(groupKey, () => []).add(
              AppDataItem(
                id: entry.path,
                name: base,
                path: entry.path,
                category: scanDir.category,
                sizeBytes: size,
                lastModified: modified,
                isDirectory: stat.type == FileSystemEntityType.directory,
                description:
                    'Orphaned ${scanDir.category.shortLabel} with no matching installed app',
                selected: true,
              ),
            );
      }
    }

    final groups = <OrphanLeftoverGroup>[];
    groupedItems.forEach((key, items) {
      items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      groups.add(
        OrphanLeftoverGroup(
          id: key,
          suspectedAppName: groupTitles[key] ?? key,
          identifier: key,
          platform: DesktopPlatformType.macos,
          confidenceReason:
              'No matching application found in /Applications or ~/Applications',
          items: items,
        ),
      );
    });

    groups.sort((a, b) => b.totalSizeBytes.compareTo(a.totalSizeBytes));
    return groups;
  }

  String _humanizeBundleId(String bundleId) {
    final parts = bundleId.split('.');
    if (parts.length >= 3) {
      final vendor = parts[1];
      final app = parts.sublist(2).join(' ');
      final capVendor =
          vendor.isNotEmpty ? vendor[0].toUpperCase() + vendor.substring(1) : '';
      final capApp =
          app.isNotEmpty ? app[0].toUpperCase() + app.substring(1) : bundleId;
      return '$capApp ($capVendor)';
    }
    return bundleId;
  }

  Future<Set<String>> _discoverHomebrewCasks() async {
    final tokens = <String>{};
    for (final path in ['/opt/homebrew/Caskroom', '/usr/local/Caskroom']) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(followLinks: false)) {
            tokens.add(
              FormatUtils.normalizeToken(FormatUtils.basename(entity.path)),
            );
          }
        } catch (_) {}
      }
    }
    return tokens;
  }

  Future<String> _fetchRunningProcessSnapshot() async {
    try {
      final res = await Process.run('ps', ['-axo', 'comm']);
      if (res.exitCode == 0) {
        return res.stdout as String;
      }
    } catch (_) {}
    return '';
  }
}
