import 'package:app_cleaner/main.dart';
import 'package:app_cleaner/models/app_models.dart';
import 'package:app_cleaner/services/app_cleaner_service.dart';
import 'package:app_cleaner/utils/platform_parsers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeAppCleanerService extends AppCleanerService {
  final List<InstalledApp> mockApps;
  final List<OrphanLeftoverGroup> mockOrphans;
  List<OperationLogEntry> savedHistory = [];

  FakeAppCleanerService({
    required this.mockApps,
    required this.mockOrphans,
  });

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
  Future<void> ensureAppDataScanned(InstalledApp app) async {
    app.dataScanned = true;
  }

  @override
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) async {
    return List<OrphanLeftoverGroup>.from(mockOrphans);
  }

  @override
  Future<CleanActionResult> clearAppData({
    required InstalledApp app,
    required bool cacheOnly,
    bool onlySelected = true,
    bool terminateIfRunning = true,
  }) async {
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
      version: '1.0.0',
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

    // 1. Default filter is User Installed apps (2 user apps including self, 1 system app)
    expect(find.text('User Apps (2)'), findsOneWidget);
    expect(find.text('System Apps (1)'), findsOneWidget);
    expect(find.text('Self-Locked'), findsOneWidget);

    // Select TestStudio Pro explicitly (since AppCleaner sorts alphabetically first)
    await tester.tap(find.text('TestStudio Pro'));
    await tester.pumpAndSettle();

    // 2. Linux additional dependency library & Registry key are displayed
    expect(find.text('libteststudio-engine0'), findsOneWidget);
    expect(find.text('TestStudio Registry Key'), findsOneWidget);

    // 3. Test Android-style "Clear Cache Only" without uninstalling app, and verify history saved!
    await tester.tap(find.textContaining('Clear Cache Only'));
    await tester.pumpAndSettle();
    expect(find.text('Clear Cache'), findsOneWidget);
    await tester.tap(find.text('Clear Cache'));
    await tester.pumpAndSettle();

    // Cache item removed, preferences and registry items remain, AND history persisted!
    expect(userApp.cacheSizeBytes, 0);
    expect(userApp.registryItemsCount, 1);
    expect(fakeService.savedHistory.length, 1);

    // 4. Select AppCleaner itself and verify Self-Locked protection!
    await tester.tap(find.text('AppCleaner').last);
    await tester.pumpAndSettle();
    expect(find.text('AppCleaner (Self-Locked)'), findsOneWidget);
    expect(find.text('Stop Process'), findsNothing);

    // 5. Switch to System Apps filter and verify Safari is shown
    await tester.tap(find.text('System Apps (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Safari'), findsWidgets);
    expect(find.text('System App (Protected)'), findsOneWidget);

    // 6. Switch to Orphaned Leftovers tab and verify layout renders cleanly
    await tester.tap(find.text('Orphaned Leftovers'));
    await tester.pumpAndSettle();
    expect(find.text('OldUninstalledApp'), findsOneWidget);
    expect(find.text('15.0 MB'), findsWidgets);
  });
}
