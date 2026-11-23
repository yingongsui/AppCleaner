import '../models/app_models.dart';

/// Provides realistic multi-platform mock applications, data/cache items,
/// Windows Registry keys, Linux additional dependency libraries, and orphaned
/// leftovers for Web UI debugging and cross-platform previewing.
class WebMockData {
  static List<LinuxDependencyPackage> _buildDbeaverSampleDeps() {
    return [
      LinuxDependencyPackage(
        packageName: 'libdbeaver-ce-core0',
        version: '2.14.0-1ubuntu1',
        sizeBytes: 18450 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description:
            'DBeaver Community core runtime shared library (auto-installed in same transaction)',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libwebkit2gtk-4.1-0',
        version: '2.44.2-0ubuntu0.24.04.1',
        sizeBytes: 64200 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description:
            'Web content engine library for GTK (no other installed packages depend on it)',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'gir1.2-ayatanaappindicator3-0.1',
        version: '0.5.93-1build3',
        sizeBytes: 420 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description: 'Ayatana Application Indicators GObject Introspection data',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libminizip1t64',
        version: '1:1.3.dfsg-3.1ubuntu2',
        sizeBytes: 156 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: false,
        description: 'Zip compression library (orphaned auto-dependency)',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libavcodec60',
        version: '7:6.1.1-3ubuntu5',
        sizeBytes: 14800 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: false,
        installedTogetherInHistory: false,
        requiredByOthers: const ['vlc', 'mpv'],
        description:
            'FFmpeg audio/video codec library (shared with other apps, kept by default)',
        selected: false,
      ),
    ];
  }

  static List<InstalledApp> buildLinuxSampleApps() {
    final dbeaverDeps = _buildDbeaverSampleDeps();
    final obsDeps = [
      LinuxDependencyPackage(
        packageName: 'libobs0t64',
        version: '30.1.2+dfsg-1build1',
        sizeBytes: 5820 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description:
            'OBS Studio core recording and streaming engine library (installed in same transaction)',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'obs-plugins',
        version: '30.1.2+dfsg-1build1',
        sizeBytes: 12400 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description: 'Official audio/video capture and filter plugins for OBS',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libmbedtls14t64',
        version: '2.28.8-1',
        sizeBytes: 890 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: true,
        description:
            'Lightweight crypto and SSL/TLS library (orphaned auto-dependency)',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libqrcodegencpp1',
        version: '1.8.0-1.2',
        sizeBytes: 112 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: true,
        installedTogetherInHistory: false,
        description: 'C++ QR code generation shared library',
        selected: true,
      ),
      LinuxDependencyPackage(
        packageName: 'libqt6widgets6t64',
        version: '6.4.2+dfsg-21.1build5',
        sizeBytes: 9450 * 1024,
        packageManager: 'apt',
        isAutoInstalled: true,
        isExclusivelyRequired: false,
        installedTogetherInHistory: false,
        requiredByOthers: const ['qbittorrent', 'wireshark'],
        description:
            'Qt 6 desktop widget toolkit (shared by qBittorrent & Wireshark, unchecked by default)',
        selected: false,
      ),
    ];

    return [
      InstalledApp(
        id: 'linux-preview:obs-studio',
        name: 'OBS Studio',
        identifier: 'com.obsproject.Studio',
        version: '30.1.2-1',
        publisher: 'APT / Ubuntu Universe (obs-studio)',
        installPath: '/usr/share/applications/com.obsproject.Studio.desktop',
        executablePath: '/usr/bin/obs',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.aptDpkg,
        platform: DesktopPlatformType.linux,
        appSizeBytes: 24600 * 1024,
        linuxPackageName: 'obs-studio',
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/home/user/.config/obs-studio',
            name: 'obs-studio',
            path: '/home/user/.config/obs-studio',
            category: DataCategory.preferences,
            sizeBytes: 18400 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 1)),
            description:
                'XDG user scene profiles, stream keys & plugin config (~/.config/obs-studio)',
          ),
          AppDataItem(
            id: '/home/user/.cache/obs-studio',
            name: 'obs-studio (shader & web cache)',
            path: '/home/user/.cache/obs-studio',
            category: DataCategory.cache,
            sizeBytes: 96500 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 5)),
            description:
                'XDG compiled shader cache & embedded browser cache (~/.cache/obs-studio)',
          ),
          AppDataItem(
            id: '/home/user/.local/state/obs-studio/logs',
            name: 'obs-studio/logs',
            path: '/home/user/.local/state/obs-studio/logs',
            category: DataCategory.logs,
            sizeBytes: 4300 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            description:
                'Runtime & stream profiler logs (~/.local/state/obs-studio/logs)',
          ),
        ],
        linuxDependencies: obsDeps,
      ),
      InstalledApp(
        id: 'linux-preview:dbeaver-ce',
        name: 'DBeaver Community',
        identifier: 'io.dbeaver.DBeaverCommunity',
        version: '24.2.0',
        publisher: 'APT / DBeaver Corp (dbeaver-ce)',
        installPath: '/usr/share/applications/dbeaver-ce.desktop',
        executablePath: '/usr/bin/dbeaver',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.aptDpkg,
        platform: DesktopPlatformType.linux,
        appSizeBytes: 142000 * 1024,
        linuxPackageName: 'dbeaver-ce',
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/home/user/.local/share/DBeaverData',
            name: 'DBeaverData',
            path: '/home/user/.local/share/DBeaverData',
            category: DataCategory.appData,
            sizeBytes: 215000 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 2)),
            description:
                'Database connections, drivers & SQL scripts workspace (~/.local/share/DBeaverData)',
          ),
          AppDataItem(
            id: '/home/user/.cache/DBeaverData',
            name: 'DBeaverData (JDBC & Metadata Cache)',
            path: '/home/user/.cache/DBeaverData',
            category: DataCategory.cache,
            sizeBytes: 68400 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 12)),
            description:
                'Temporary unpacked JDBC drivers & metadata cache (~/.cache/DBeaverData)',
          ),
        ],
        linuxDependencies: dbeaverDeps,
      ),
      InstalledApp(
        id: 'linux-preview:gnome-control-center',
        name: 'GNOME Settings',
        identifier: 'org.gnome.Settings',
        version: '46.2',
        publisher: 'GNOME Project (gnome-control-center)',
        installPath: '/usr/share/applications/org.gnome.Settings.desktop',
        executablePath: '/usr/bin/gnome-control-center',
        origin: AppOriginType.systemApp,
        installSource: InstallSource.systemBuiltIn,
        platform: DesktopPlatformType.linux,
        appSizeBytes: 19200 * 1024,
        linuxPackageName: 'gnome-control-center',
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/home/user/.cache/gnome-control-center',
            name: 'gnome-control-center',
            path: '/home/user/.cache/gnome-control-center',
            category: DataCategory.cache,
            sizeBytes: 3400 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 4)),
            description: 'GNOME Control Center panel thumbnail cache',
          ),
        ],
      ),
    ];
  }

  static List<InstalledApp> buildMacOsSampleApps() {
    return [
      InstalledApp(
        id: 'mac-preview:appcleaner',
        name: 'AppCleaner',
        identifier: 'com.yin.appcleaner',
        version: '1.0.0',
        publisher: 'Yin',
        installPath: '/Applications/AppCleaner.app',
        executablePath:
            '/Applications/AppCleaner.app/Contents/MacOS/AppCleaner',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.appBundle,
        platform: DesktopPlatformType.macos,
        appSizeBytes: 22 * 1024 * 1024,
        isSelfApp: true,
        isRunning: true,
        dataScanned: true,
      ),
      InstalledApp(
        id: 'mac-preview:vscode',
        name: 'Visual Studio Code',
        identifier: 'com.microsoft.VSCode',
        version: '1.95.2',
        publisher: 'Microsoft',
        installPath: '/Applications/Visual Studio Code.app',
        executablePath:
            '/Applications/Visual Studio Code.app/Contents/MacOS/Electron',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.homebrewCask,
        platform: DesktopPlatformType.macos,
        appSizeBytes: 540 * 1024 * 1024,
        isRunning: true,
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/Users/yin/Library/Application Support/Code',
            name: 'Code',
            path: '/Users/yin/Library/Application Support/Code',
            category: DataCategory.appData,
            sizeBytes: 420 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            description:
                'Application core data, workspace state & local history',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Caches/com.microsoft.VSCode',
            name: 'com.microsoft.VSCode',
            path: '/Users/yin/Library/Caches/com.microsoft.VSCode',
            category: DataCategory.cache,
            sizeBytes: 285 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(minutes: 40)),
            description: 'Application runtime cache & VSIX download cache',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Preferences/com.microsoft.VSCode.plist',
            name: 'com.microsoft.VSCode.plist',
            path: '/Users/yin/Library/Preferences/com.microsoft.VSCode.plist',
            category: DataCategory.preferences,
            sizeBytes: 48 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 1)),
            description: 'User preference property list (.plist)',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Saved Application State/com.microsoft.VSCode.savedState',
            name: 'com.microsoft.VSCode.savedState',
            path:
                '/Users/yin/Library/Saved Application State/com.microsoft.VSCode.savedState',
            category: DataCategory.savedState,
            sizeBytes: 3800 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 3)),
            description: 'Saved window geometry & restoration state',
          ),
        ],
      ),
      InstalledApp(
        id: 'mac-preview:wechat',
        name: 'WeChat',
        identifier: 'com.tencent.xinWeChat',
        version: '3.8.9',
        publisher: 'Tencent',
        installPath: '/Applications/WeChat.app',
        executablePath: '/Applications/WeChat.app/Contents/MacOS/WeChat',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.appStore,
        platform: DesktopPlatformType.macos,
        appSizeBytes: 710 * 1024 * 1024,
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/Users/yin/Library/Containers/com.tencent.xinWeChat',
            name: 'com.tencent.xinWeChat',
            path: '/Users/yin/Library/Containers/com.tencent.xinWeChat',
            category: DataCategory.container,
            sizeBytes: 1840 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            description:
                'macOS App Sandbox container directory (messages & media files)',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Caches/com.tencent.xinWeChat',
            name: 'com.tencent.xinWeChat (Caches)',
            path: '/Users/yin/Library/Caches/com.tencent.xinWeChat',
            category: DataCategory.cache,
            sizeBytes: 512 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 4)),
            description: 'Image/video thumbnails & mini-program cache',
          ),
        ],
      ),
      InstalledApp(
        id: 'mac-preview:safari',
        name: 'Safari',
        identifier: 'com.apple.Safari',
        version: '18.1',
        publisher: 'Apple Inc.',
        installPath: '/System/Applications/Safari.app',
        executablePath: '/System/Applications/Safari.app/Contents/MacOS/Safari',
        origin: AppOriginType.systemApp,
        installSource: InstallSource.systemBuiltIn,
        platform: DesktopPlatformType.macos,
        appSizeBytes: 68 * 1024 * 1024,
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: '/Users/yin/Library/Caches/com.apple.Safari',
            name: 'com.apple.Safari',
            path: '/Users/yin/Library/Caches/com.apple.Safari',
            category: DataCategory.cache,
            sizeBytes: 340 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 6)),
            description: 'Safari offline web cache & assets',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Saved Application State/com.apple.Safari.savedState',
            name: 'com.apple.Safari.savedState',
            path:
                '/Users/yin/Library/Saved Application State/com.apple.Safari.savedState',
            category: DataCategory.savedState,
            sizeBytes: 2100 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 1)),
            description: 'Window session & tab restoration state',
          ),
        ],
      ),
    ];
  }

  static List<InstalledApp> buildWindowsSampleApps() {
    return [
      InstalledApp(
        id: 'win-preview:discord',
        name: 'Discord',
        identifier: 'Discord',
        version: '1.0.9168',
        publisher: 'Discord Inc.',
        installPath: r'C:\Users\yin\AppData\Local\Discord',
        executablePath: r'C:\Users\yin\AppData\Local\Discord\Update.exe',
        origin: AppOriginType.userInstalled,
        installSource: InstallSource.win32Registry,
        platform: DesktopPlatformType.windows,
        appSizeBytes: 310 * 1024 * 1024,
        uninstallCommandHint:
            r'C:\Users\yin\AppData\Local\Discord\Update.exe --uninstall',
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: r'C:\Users\yin\AppData\Roaming\discord',
            name: 'discord (Roaming Config & LocalStorage)',
            path: r'C:\Users\yin\AppData\Roaming\discord',
            category: DataCategory.preferences,
            sizeBytes: 128 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 5)),
            description:
                'Windows Roaming AppData user session & settings (%APPDATA%)',
          ),
          AppDataItem(
            id: r'C:\Users\yin\AppData\Roaming\discord\Cache',
            name: 'discord/Cache & Code Cache',
            path: r'C:\Users\yin\AppData\Roaming\discord\Cache',
            category: DataCategory.cache,
            sizeBytes: 620 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            description: 'Multimedia voice & channel image cache',
          ),
          AppDataItem(
            id: r'reg:HKCU\Software\Discord',
            name: 'Discord (HKCU Registry Hive)',
            path: r'HKCU\Software\Discord',
            category: DataCategory.registry,
            sizeBytes: 24 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 1)),
            description:
                'Current User Windows Registry configuration & protocol handlers (18 values/subkeys)',
          ),
          AppDataItem(
            id: r'reg:HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Discord',
            name: 'Discord (Uninstall Registry Key)',
            path:
                r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Discord',
            category: DataCategory.registry,
            sizeBytes: 8 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 10)),
            description: 'Windows Uninstall Registry entry (HKCU)',
          ),
        ],
      ),
      InstalledApp(
        id: 'win-preview:edge-webview',
        name: 'Microsoft Edge WebView2 Runtime',
        identifier: 'Microsoft.EdgeWebView2',
        version: '130.0.2849.80',
        publisher: 'Microsoft Corporation',
        installPath:
            r'C:\Program Files (x86)\Microsoft\EdgeWebView\Application',
        origin: AppOriginType.systemApp,
        installSource: InstallSource.systemBuiltIn,
        platform: DesktopPlatformType.windows,
        appSizeBytes: 490 * 1024 * 1024,
        dataScanned: true,
        dataItems: [
          AppDataItem(
            id: r'C:\Users\yin\AppData\Local\Microsoft\EdgeWebView',
            name: 'EdgeWebView Cache',
            path: r'C:\Users\yin\AppData\Local\Microsoft\EdgeWebView',
            category: DataCategory.cache,
            sizeBytes: 94 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 2)),
            description: 'WebView2 system runtime shared rendering cache',
          ),
        ],
      ),
    ];
  }

  static List<InstalledApp> buildAllSampleApps() {
    return [
      ...buildMacOsSampleApps(),
      ...buildLinuxSampleApps(),
      ...buildWindowsSampleApps(),
    ];
  }

  static List<OrphanLeftoverGroup> buildSampleOrphanGroups() {
    return [
      OrphanLeftoverGroup(
        id: 'com.spotify.client',
        suspectedAppName: 'Spotify (Uninstalled Leftovers)',
        identifier: 'com.spotify.client',
        platform: DesktopPlatformType.macos,
        confidenceReason:
            'No matching application found in /Applications or ~/Applications',
        items: [
          AppDataItem(
            id: '/Users/yin/Library/Application Support/Spotify',
            name: 'Spotify',
            path: '/Users/yin/Library/Application Support/Spotify',
            category: DataCategory.appData,
            sizeBytes: 412 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 15)),
            description: 'Orphaned application support directory',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Caches/com.spotify.client',
            name: 'com.spotify.client',
            path: '/Users/yin/Library/Caches/com.spotify.client',
            category: DataCategory.cache,
            sizeBytes: 1260 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 15)),
            description: 'Orphaned offline audio cache',
          ),
          AppDataItem(
            id: '/Users/yin/Library/Preferences/com.spotify.client.plist',
            name: 'com.spotify.client.plist',
            path: '/Users/yin/Library/Preferences/com.spotify.client.plist',
            category: DataCategory.preferences,
            sizeBytes: 32 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 16)),
            description: 'Orphaned preference property list (.plist)',
          ),
        ],
      ),
      OrphanLeftoverGroup(
        id: 'org.gimp.GIMP',
        suspectedAppName: 'GIMP Image Editor (Linux Leftovers)',
        identifier: 'org.gimp.GIMP',
        platform: DesktopPlatformType.linux,
        confidenceReason:
            'Corresponding DEB/Flatpak package was uninstalled, leaving XDG files',
        items: [
          AppDataItem(
            id: '/home/user/.config/GIMP/2.10',
            name: 'GIMP/2.10',
            path: '/home/user/.config/GIMP/2.10',
            category: DataCategory.preferences,
            sizeBytes: 64 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 24)),
            description: 'Orphaned GIMP brushes, workspace layout & plugin config',
          ),
          AppDataItem(
            id: '/home/user/.cache/gimp',
            name: 'gimp',
            path: '/home/user/.cache/gimp',
            category: DataCategory.cache,
            sizeBytes: 215 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 24)),
            description: 'Orphaned GIMP swap & thumbnail cache',
          ),
        ],
      ),
      OrphanLeftoverGroup(
        id: 'win.videolan.vlc',
        suspectedAppName: 'VLC Media Player (Windows File & Registry Leftovers)',
        identifier: r'VideoLAN\VLC',
        platform: DesktopPlatformType.windows,
        confidenceReason:
            'Not found in Windows Uninstall Registry keys or MSIX packages',
        items: [
          AppDataItem(
            id: r'C:\Users\yin\AppData\Roaming\vlc',
            name: 'vlc (Roaming AppData)',
            path: r'C:\Users\yin\AppData\Roaming\vlc',
            category: DataCategory.preferences,
            sizeBytes: 38 * 1024 * 1024,
            lastModified: DateTime.now().subtract(const Duration(days: 30)),
            description: 'Orphaned VLC shader cache & configuration in %APPDATA%',
          ),
          AppDataItem(
            id: r'reg:HKCU\Software\VideoLAN\VLC',
            name: r'VideoLAN\VLC (Registry Key)',
            path: r'HKCU\Software\VideoLAN\VLC',
            category: DataCategory.registry,
            sizeBytes: 16 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 30)),
            description:
                'Orphaned Windows Registry hive in HKCU\\Software (14 entries)',
          ),
          AppDataItem(
            id: r'reg:HKLM\Software\WOW6432Node\VideoLAN\VLC',
            name: r'WOW6432Node\VideoLAN\VLC (Registry Key)',
            path: r'HKLM\Software\WOW6432Node\VideoLAN\VLC',
            category: DataCategory.registry,
            sizeBytes: 12 * 1024,
            isDirectory: false,
            lastModified: DateTime.now().subtract(const Duration(days: 30)),
            description:
                'Orphaned 32-bit Machine Registry hive in HKLM\\Software\\WOW6432Node',
          ),
        ],
      ),
    ];
  }
}
