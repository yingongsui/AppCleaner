import 'package:app_cleaner/main.dart';
import 'package:app_cleaner/models/app_models.dart';
import 'package:app_cleaner/services/app_cleaner_service.dart';
import 'package:app_cleaner/utils/format_utils.dart';
import 'package:app_cleaner/utils/platform_parsers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeAppCleanerService extends AppCleanerService {
  final List<InstalledApp> mockApps;
  final List<OrphanLeftoverGroup> mockOrphans;
  List<OperationLogEntry> savedHistory = [];
  AppCleanerSettings savedSettings = const AppCleanerSettings();
  bool? lastClearMoveToTrash;
  bool? lastOrphanMoveToTrash;

  FakeAppCleanerService({
    required this.mockApps,
    required this.mockOrphans,
  });

  @override
  Future<AppCleanerSettings> loadSettings() async => savedSettings;

  @override
  Future<void> saveSettings(AppCleanerSettings settings) async {
    savedSettings = settings;
  }

  @override
  List<String> getBuiltInWhitelist() => const ['icloud', 'webkit', 'systemd'];

  @override
  String getConfigDirectoryPath() => '/tmp/AppCleaner';

  @override
  Future<List<OperationLogEntry>> loadOperationHistory() async {
    return List<OperationLogEntry>.from(savedHistory);
  }

  @override
  Future<void> saveOperationHistory(List<OperationLogEntry> entries) async {
    savedHistory = List<OperationLogEntry>.from(entries);
  }

  @override
  Future<void> clearOperationHistory() async {
    savedHistory = [];
  }

  @override
  Future<List<InstalledApp>> scanInstalledApps({
    DesktopPlatformType? filterPlatform,
  }) async {
    return List<InstalledApp>.from(mockApps);
  }

  @override
  Future<void> ensureAppDataScanned(
    InstalledApp app, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    app.dataScanned = true;
  }

  @override
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps, {
    AppCleanerSettings settings = const AppCleanerSettings(),
  }) async {
    return List<OrphanLeftoverGroup>.from(mockOrphans);
  }

  @override
  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
    bool moveToTrash = true,
  }) async {
    lastClearMoveToTrash = moveToTrash;
    final targets = app.dataItems.where((item) {
      if (cacheOnly && !item.isCacheLike) return false;
      if (onlySelected && !item.selected) return false;
      return true;
    }).toList();
    int freed = 0;
    for (final item in targets) {
      freed += item.sizeBytes;
      app.dataItems.remove(item);
    }
    return CleanActionResult(
      success: true,
      deletedCount: targets.length,
      freedBytes: freed,
      summaryMessage: 'Cleaned ${targets.length} items.',
    );
  }

  @override
  Future<CleanActionResult> cleanOrphanLeftovers(
    List<OrphanLeftoverGroup> groups, {
    bool moveToTrash = true,
  }) async {
    lastOrphanMoveToTrash = moveToTrash;
    int freed = 0;
    int deleted = 0;
    for (final group in groups) {
      final targets = group.items.where((i) => i.selected).toList();
      for (final item in targets) {
        freed += item.sizeBytes;
        deleted++;
        group.items.remove(item);
      }
    }
    return CleanActionResult(
      success: true,
      deletedCount: deleted,
      freedBytes: freed,
      summaryMessage: 'Cleaned $deleted orphaned items.',
    );
  }
}

void main() {
  group('Platform parsers & Linux dependency analyzer unit tests', () {
    test('Parses macOS XML Info.plist key-values accurately', () {
      const samplePlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Visual Studio Code</string>
  <key>CFBundleIdentifier</key>
  <string>com.microsoft.VSCode</string>
  <key>CFBundleShortVersionString</key>
  <string>1.95.0</string>
</dict>
</plist>
''';
      final parsed = PlatformParsers.parseXmlPlist(samplePlist);
      expect(parsed['CFBundleDisplayName'], 'Visual Studio Code');
      expect(parsed['CFBundleIdentifier'], 'com.microsoft.VSCode');
      expect(parsed['CFBundleShortVersionString'], '1.95.0');
    });

    test('Parses Linux .desktop file content accurately', () {
      const desktopContent = '''
[Desktop Entry]
Name=VLC media player
Exec=/usr/bin/vlc --started-from-file %U
Icon=vlc
Type=Application
Categories=AudioVideo;Player;Recorder;
''';
      final fields = PlatformParsers.parseDesktopEntry(desktopContent);
      expect(fields['Name'], 'VLC media player');
      expect(fields['Exec'], '/usr/bin/vlc --started-from-file %U');
      expect(fields['Categories'], 'AudioVideo;Player;Recorder;');
    });

    test('Parses /var/log/apt/history.log for companion auto-installed libs',
        () {
      const aptLog = '''
Start-Date: 2026-11-20  10:15:04
Commandline: apt install obs-studio
Requested-By: user (1000)
Install: libobs0t64:amd64 (30.1.2-1, automatic), obs-plugins:amd64 (30.1.2-1, automatic), obs-studio:amd64 (30.1.2-1), libqrcodegencpp1:amd64 (1.8.0-1, automatic)
End-Date: 2026-11-20  10:15:22
''';
      final companions = PlatformParsers.parseAptHistoryCompanions(
        aptLog,
        'obs-studio',
      );
      expect(
        companions,
        containsAll(['libobs0t64', 'obs-plugins', 'libqrcodegencpp1']),
      );
      expect(companions.contains('obs-studio'), isFalse);
    });

    test('Builds Linux uninstall command including selected additional libs',
        () {
      final app = InstalledApp(
        id: 'linux-preview:obs',
        name: 'OBS Studio',
        identifier: 'obs-studio',
        installPath: '/usr/share/applications/obs.desktop',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.aptDpkg,
        platform: DesktopPlatformType.linux,
        linuxPackageName: 'obs-studio',
      );
      final deps = [
        LinuxDependencyPackage(
          packageName: 'libobs0t64',
          version: '30.1.2',
          sizeBytes: 1024,
          packageManager: 'apt',
          isAutoInstalled: true,
          isExclusivelyRequired: true,
          selected: true,
        ),
      ];
      final cmd = PlatformParsers.buildLinuxUninstallCommand(
        app: app,
        selectedDependencies: deps,
      );
      expect(
        cmd,
        equals([
          'pkexec',
          'apt-get',
          'purge',
          '-y',
          '--auto-remove',
          'obs-studio',
          'libobs0t64',
        ]),
      );
    });

    test('Guards critical Windows Registry hives from accidental deletion', () {
      expect(
        PlatformParsers.isSafeWindowsRegistryKeyPath(r'HKCU\Software\Discord'),
        isTrue,
      );
      expect(
        PlatformParsers.isSafeWindowsRegistryKeyPath(
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Discord',
        ),
        isTrue,
      );
      expect(
        PlatformParsers.isSafeWindowsRegistryKeyPath(r'HKCU\Software'),
        isFalse,
      );
      expect(
        PlatformParsers.isSafeWindowsRegistryKeyPath(
          r'HKLM\Software\Microsoft\Windows',
        ),
        isFalse,
      );
      expect(
        PlatformParsers.isSafeWindowsRegistryKeyPath(
          r'HKLM\Software\WOW6432Node',
        ),
        isFalse,
      );
    });

    test('Serializes and deserializes OperationLogEntry JSON cleanly', () {
      final entry = OperationLogEntry(
        timestamp: DateTime.utc(2026, 11, 23, 12, 30),
        title: 'Uninstall App & Leftovers: BetterDisplay',
        result: const CleanActionResult(
          success: true,
          deletedCount: 3,
          freedBytes: 56 * 1024 * 1024,
          deletedPaths: ['/Applications/BetterDisplay.app'],
          summaryMessage: 'Uninstalled BetterDisplay.',
        ),
      );
      final restored = OperationLogEntry.fromJson(entry.toJson());
      expect(restored.title, entry.title);
      expect(restored.result.freedBytes, 56 * 1024 * 1024);
      expect(restored.result.deletedPaths, ['/Applications/BetterDisplay.app']);
    });

    test('Parses human-readable package sizes across KB/MB/GB/MiB', () {
      expect(FormatUtils.parseHumanSize('12.5 MiB'), (12.5 * 1024 * 1024).round());
      expect(FormatUtils.parseHumanSize('480 kB'), 480 * 1024);
      expect(FormatUtils.parseHumanSize('1.5 GB'), (1.5 * 1024 * 1024 * 1024).round());
    });

    test(
        'Matches versioned and channel-suffixed config folders (e.g. LyX-2.4) against installed apps',
        () {
      expect(PlatformParsers.stripVersionAndChannelSuffix('LyX-2.4'), 'LyX');
      expect(PlatformParsers.stripVersionAndChannelSuffix('lyx2.4'), 'lyx');
      expect(PlatformParsers.stripVersionAndChannelSuffix('GIMP-2.10'), 'GIMP');
      expect(
        PlatformParsers.stripVersionAndChannelSuffix('Blender 4.2'),
        'Blender',
      );
      expect(
        PlatformParsers.stripVersionAndChannelSuffix('python3.12'),
        'python',
      );
      expect(
        PlatformParsers.stripVersionAndChannelSuffix('discord-canary'),
        'discord',
      );

      final installed = <String>{};
      PlatformParsers.addNormalizedAppTokens(installed, 'LyX');
      PlatformParsers.addNormalizedAppTokens(installed, 'GIMP');
      PlatformParsers.addNormalizedAppTokens(installed, 'python3');

      expect(
        PlatformParsers.matchesInstalledIdentifier('LyX-2.4', installed),
        isTrue,
      );
      expect(
        PlatformParsers.matchesInstalledIdentifier('lyx2.4.1', installed),
        isTrue,
      );
      expect(
        PlatformParsers.matchesInstalledIdentifier('org.lyx.LyX-2.4', installed),
        isTrue,
      );
      expect(
        PlatformParsers.matchesInstalledIdentifier('GIMP-2.10', installed),
        isTrue,
      );
      expect(
        PlatformParsers.matchesInstalledIdentifier('python3.12', installed),
        isTrue,
      );
      // Uninstalled app should NOT match (properly flagged as orphan)
      expect(
        PlatformParsers.matchesInstalledIdentifier('Softdeluxe-3.0', installed),
        isFalse,
      );
      expect(
        PlatformParsers.matchesInstalledIdentifier('LyX-2.4', {'firefox'}),
        isFalse,
      );
    });

    test('Persists AppCleanerSettings whitelist and manual app associations cleanly',
        () {
      const settings = AppCleanerSettings(
        scanVendorSubfolders: false,
        customWhitelist: ['/Users/yin/Library/Application Support/KeepMe'],
        customAssociations: [
          CustomAppAssociation(
            path: '/Users/yin/Library/Application Support/Softdeluxe',
            label: 'Softdeluxe',
            category: DataCategory.appData,
            appId: 'app:fdm',
            appIdentifier: 'org.freedownloadmanager.fdm6',
            appName: 'Free Download Manager',
          ),
        ],
      );
      final restored = AppCleanerSettings.fromJson(settings.toJson());
      expect(restored.scanVendorSubfolders, isFalse);
      expect(
        restored.isWhitelisted(
          '/Users/yin/Library/Application Support/KeepMe/sub',
        ),
        isTrue,
      );
      final fdm = InstalledApp(
        id: 'app:fdm',
        name: 'Free Download Manager',
        identifier: 'org.freedownloadmanager.fdm6',
        installPath: '/Applications/Free Download Manager.app',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.appBundle,
        platform: DesktopPlatformType.macos,
      );
      expect(
        restored.isAssociatedWithInstalledApp(
          '/Users/yin/Library/Application Support/Softdeluxe',
          [fdm],
        ),
        isTrue,
      );
      expect(restored.associationsForApp(fdm).length, 1);
    });
  });

  testWidgets(
      'AppCleaner UI distinguishes User vs System apps, clears cache/data/registry without uninstalling, and shows Linux deps',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final userApp = InstalledApp(
      id: 'linux-preview:test-app',
      name: 'TestStudio Pro',
      identifier: 'com.example.teststudio',
      version: '2.1.0',
      publisher: 'Example Corp',
      installPath: '/Applications/TestStudio.app',
      origin: AppOriginType.userInstalled,
      installSource: InstallSource.aptDpkg,
      platform: DesktopPlatformType.linux,
      appSizeBytes: 50 * 1024 * 1024,
      linuxPackageName: 'teststudio',
      dataScanned: true,
      dataItems: [
        AppDataItem(
          id: '/tmp/teststudio/config',
          name: 'teststudio-config',
          path: '/tmp/teststudio/config',
          category: DataCategory.preferences,
          sizeBytes: 10 * 1024 * 1024,
        ),
        AppDataItem(
          id: '/tmp/teststudio/cache',
          name: 'teststudio-cache',
          path: '/tmp/teststudio/cache',
          category: DataCategory.cache,
          sizeBytes: 25 * 1024 * 1024,
        ),
        AppDataItem(
          id: r'reg:HKCU\Software\TestStudio',
          name: 'TestStudio Registry Key',
          path: r'HKCU\Software\TestStudio',
          category: DataCategory.registry,
          sizeBytes: 16 * 1024,
          isDirectory: false,
        ),
      ],
      linuxDependencies: [
        LinuxDependencyPackage(
          packageName: 'libteststudio-engine0',
          version: '2.1.0-1',
          sizeBytes: 12 * 1024 * 1024,
          packageManager: 'apt',
          isAutoInstalled: true,
          isExclusivelyRequired: true,
          installedTogetherInHistory: true,
          description: 'TestStudio dedicated rendering engine library',
        ),
      ],
    );

    final systemApp = InstalledApp(
      id: 'sys:safari',
      name: 'Safari',
      identifier: 'com.apple.Safari',
      version: '18.0',
      publisher: 'Apple Inc.',
      installPath: '/System/Applications/Safari.app',
      origin: AppOriginType.systemApp,
      installSource: InstallSource.systemBuiltIn,
      platform: DesktopPlatformType.macos,
      appSizeBytes: 30 * 1024 * 1024,
      dataScanned: true,
    );

    final selfApp = InstalledApp(
      id: 'self:appcleaner',
      name: 'AppCleaner',
      identifier: 'com.yin.appcleaner',
      version: '1.1.0',
      publisher: 'Yin',
      installPath: '/Applications/AppCleaner.app',
      origin: AppOriginType.userInstalled,
      installSource: InstallSource.appBundle,
      platform: DesktopPlatformType.macos,
      appSizeBytes: 22 * 1024 * 1024,
      isSelfApp: true,
      isRunning: true,
      dataScanned: true,
    );

    final fakeService = FakeAppCleanerService(
      mockApps: [userApp, selfApp, systemApp],
      mockOrphans: [
        OrphanLeftoverGroup(
          id: 'com.old.uninstalled',
          suspectedAppName: 'OldUninstalledApp',
          identifier: 'com.old.uninstalled',
          platform: DesktopPlatformType.macos,
          confidenceReason: 'No matching installed application found',
          items: [
            AppDataItem(
              id: '/tmp/orphan/cache',
              name: 'com.old.uninstalled',
              path: '/tmp/orphan/cache',
              category: DataCategory.cache,
              sizeBytes: 15 * 1024 * 1024,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(AppCleanerApp(service: fakeService));
    await tester.pumpAndSettle();

    // 1. Default filter is User Installed apps (2-line segments: title on top, count below)
    expect(find.text('User Apps'), findsOneWidget);
    expect(find.text('System Apps'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Self-Locked'), findsOneWidget);

    // Select TestStudio Pro explicitly (since AppCleaner sorts alphabetically first)
    await tester.tap(find.text('TestStudio Pro'));
    await tester.pumpAndSettle();

    // 2. Linux additional dependency library & Registry key are displayed
    expect(find.text('libteststudio-engine0'), findsOneWidget);
    expect(find.text('TestStudio Registry Key'), findsOneWidget);

    // 3. Test Android-style "Clear Cache Only" without uninstalling app, verify Move to Trash default & history saved!
    await tester.tap(find.textContaining('Clear Cache Only'));
    await tester.pumpAndSettle();
    expect(find.text('Move to System Trash (Recoverable)'), findsOneWidget);
    expect(find.text('Clear Cache (Move to Trash)'), findsOneWidget);
    await tester.tap(find.text('Clear Cache (Move to Trash)'));
    await tester.pumpAndSettle();

    // Cache item removed (via Move to Trash default), preferences and registry items remain, history persisted, and floating capsule toast shown!
    expect(fakeService.lastClearMoveToTrash, isTrue);
    expect(userApp.cacheSizeBytes, 0);
    expect(userApp.registryItemsCount, 1);
    expect(fakeService.savedHistory.length, 1);
    expect(find.text('Cleaned 1 items.'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Cleaned 1 items.'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is StadiumBorder,
        ),
      ),
      findsOneWidget,
    );

    // 4. Select AppCleaner itself and verify Self-Locked protection & top-aligned detail pane!
    await tester.tap(find.text('AppCleaner').last);
    await tester.pumpAndSettle();
    expect(find.text('AppCleaner (Self-Locked)'), findsOneWidget);
    expect(find.text('Stop Process'), findsNothing);
    // Detail header card should be top-aligned (near y=0, not vertically centered)
    final detailVersionTop = tester.getTopLeft(find.text('v1.1.0')).dy;
    expect(detailVersionTop, lessThan(120));

    // 5. Switch to System Apps filter and verify Safari is shown
    await tester.tap(find.text('System Apps'));
    await tester.pumpAndSettle();
    expect(find.text('Safari'), findsWidgets);
    expect(find.text('System App (Protected)'), findsOneWidget);

    // 6. Switch to Orphaned Leftovers tab: verify cards collapsed by default & deselected!
    await tester.tap(find.text('Orphaned Leftovers'));
    await tester.pumpAndSettle();
    expect(find.text('OldUninstalledApp'), findsOneWidget);
    // Card is collapsed by default: child path is not rendered yet, only group header shows 15.0 MB
    expect(find.text('15.0 MB'), findsOneWidget);
    expect(find.textContaining('/tmp/orphan/cache'), findsNothing);
    expect(find.text('Clean Selected (0 items · 0 B)'), findsOneWidget);

    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Clean Selected (1 items'));
    await tester.pumpAndSettle();

    // Defaults to Move to System Trash (Recoverable)
    expect(find.text('Move to System Trash (Recoverable)'), findsOneWidget);
    expect(find.text('Move to Trash'), findsOneWidget);
    // Toggle off -> Permanently Delete (Irreversible)
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Permanently Delete (Irreversible)'), findsOneWidget);
    expect(find.text('Delete Permanently'), findsOneWidget);
    // Toggle back on -> Move to Trash and confirm
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(fakeService.lastOrphanMoveToTrash, isTrue);

    // 7. Navigate to Settings below Activity History and verify options, whitelist & About
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect 1-Level Vendor Subfolders'), findsOneWidget);
    expect(find.textContaining('Whitelist Rules'), findsOneWidget);
    expect(find.text('About AppCleaner'), findsOneWidget);
  });

  testWidgets(
      'Orphaned Leftovers right-click context menu supports Associate with App and Add to Whitelist',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fdmApp = InstalledApp(
      id: 'app:fdm',
      name: 'Free Download Manager',
      identifier: 'org.freedownloadmanager.fdm6',
      installPath: '/Applications/Free Download Manager.app',
      origin: AppOriginType.userInstalled,
      installSource: InstallSource.appBundle,
      platform: DesktopPlatformType.macos,
      dataScanned: true,
    );

    final fakeService = FakeAppCleanerService(
      mockApps: [fdmApp],
      mockOrphans: [
        OrphanLeftoverGroup(
          id: 'softdeluxe',
          suspectedAppName: 'Softdeluxe',
          identifier: 'softdeluxe',
          platform: DesktopPlatformType.macos,
          confidenceReason: 'No matching application found',
          items: [
            AppDataItem(
              id: '/Users/yin/Library/Application Support/Softdeluxe',
              name: 'Softdeluxe',
              path: '/Users/yin/Library/Application Support/Softdeluxe',
              category: DataCategory.appData,
              sizeBytes: 556 * 1024,
            ),
          ],
        ),
        OrphanLeftoverGroup(
          id: 'customtool',
          suspectedAppName: 'CustomToolData',
          identifier: 'customtool',
          platform: DesktopPlatformType.macos,
          confidenceReason: 'No matching application found',
          items: [
            AppDataItem(
              id: '/Users/yin/Library/Application Support/CustomToolData',
              name: 'CustomToolData',
              path: '/Users/yin/Library/Application Support/CustomToolData',
              category: DataCategory.appData,
              sizeBytes: 128 * 1024,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(AppCleanerApp(service: fakeService));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orphaned Leftovers'));
    await tester.pumpAndSettle();

    // Right-click Softdeluxe card -> Associate with Free Download Manager
    await tester.ensureVisible(find.text('Softdeluxe'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Softdeluxe'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Associate "Softdeluxe" with App...'), findsOneWidget);
    expect(find.text('Add to Whitelist'), findsOneWidget);

    await tester.tap(find.text('Associate "Softdeluxe" with App...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free Download Manager').last);
    await tester.pumpAndSettle();

    expect(find.text('Softdeluxe'), findsNothing);
    expect(fakeService.savedSettings.customAssociations.length, 1);
    expect(
      fdmApp.dataItems.any((d) => d.name == 'Softdeluxe'),
      isTrue,
    );

    // Right-click CustomToolData card -> Add to Whitelist
    await tester.ensureVisible(find.text('CustomToolData'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('CustomToolData'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Whitelist'));
    await tester.pumpAndSettle();

    expect(find.text('CustomToolData'), findsNothing);
    expect(
      fakeService.savedSettings.customWhitelist,
      contains('/Users/yin/Library/Application Support/CustomToolData'),
    );
  });

  testWidgets('Half-screen compact layout renders cleanly without overflow and top-aligns details',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(740, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeService = FakeAppCleanerService(
      mockApps: [
        InstalledApp(
          id: 'self:appcleaner',
          name: 'AppCleaner',
          identifier: 'com.yin.appcleaner',
          version: '1.1.0',
          publisher: 'Yin',
          installPath: '/Applications/AppCleaner.app',
          origin: AppOriginType.userInstalled,
          installSource: InstallSource.appBundle,
          platform: DesktopPlatformType.macos,
          appSizeBytes: 22 * 1024 * 1024,
          isSelfApp: true,
          isRunning: true,
          dataScanned: true,
          dataItems: [
            AppDataItem(
              id: '/home/user/snap/firefox',
              name: 'snap/firefox',
              path: '/home/user/snap/firefox',
              category: DataCategory.container,
              sizeBytes: 606 * 1024 * 1024,
              description: 'Snap container user data & revisions (~/snap/firefox)',
            ),
          ],
        ),
      ],
      mockOrphans: [
        OrphanLeftoverGroup(
          id: 'softdeluxe',
          suspectedAppName: 'Softdeluxe',
          identifier: 'softdeluxe',
          platform: DesktopPlatformType.macos,
          confidenceReason: 'No matching application found in /Applications',
          items: [
            AppDataItem(
              id: '/Users/yin/Library/Application Support/Softdeluxe',
              name: 'Softdeluxe',
              path: '/Users/yin/Library/Application Support/Softdeluxe',
              category: DataCategory.appData,
              sizeBytes: 556 * 1024,
              selected: true,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(AppCleanerApp(service: fakeService));
    await tester.pumpAndSettle();

    // Compact rail is active, detail header sits near the top (top-aligned, not centered)
    final versionTop = tester.getTopLeft(find.text('v1.1.0')).dy;
    expect(versionTop, lessThan(120));

    // Data item name ('snap/firefox') gets full width instead of wrapping 1 char per line
    final snapItemSize = tester.getSize(find.text('snap/firefox'));
    expect(snapItemSize.height, lessThan(36));

    // Switch to Orphaned Leftovers via compact rail icon and confirm clean half-screen layout + default deselected
    await tester.tap(find.byIcon(Icons.auto_delete_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Orphaned Leftovers Scanner'), findsOneWidget);
    expect(find.text('Clean Selected (0 items · 0 B)'), findsOneWidget);
  });
}
