import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/io_file_utils.dart';
import '../utils/platform_parsers.dart';

/// Scans Windows installed applications via Registry Uninstall keys and Appx/MSIX packages,
/// distinguishes User Installed Apps vs System Apps, scans %APPDATA% & %LOCALAPPDATA% data/cache,
/// scans associated Windows Registry keys (HKCU/HKLM), and detects orphaned file & registry leftovers.
class WindowsAppScanner {
  String get _appDataRoaming =>
      Platform.environment['APPDATA'] ?? r'C:\Users\Default\AppData\Roaming';
  String get _appDataLocal =>
      Platform.environment['LOCALAPPDATA'] ?? r'C:\Users\Default\AppData\Local';
  String get _programData =>
      Platform.environment['ProgramData'] ?? r'C:\ProgramData';

  static const Set<String> _ignoredWindowsOrphanDirs = {
    'Microsoft',
    'Windows',
    'Packages',
    'Temp',
    'ConnectedDevicesPlatform',
    'Comms',
    'D3DSCache',
    'Diagnostics',
    'ElevatedDiagnostics',
    'FontCache',
    'Google',
    'History',
    'IconCache.db',
    'IdentityNexusIntegration',
    'Intel',
    'NVIDIA',
    'NVIDIA Corporation',
    'AMD',
    'PeerDistRepub',
    'PlaceholderTileLogoFolder',
    'Publishers',
    'SquirrelTemp',
    'VirtualStore',
    'cef_cache',
    'pip',
    'npm',
    'npm-cache',
    'yarn',
    'Flutter',
    'Dart',
    'Pub',
    'Classes',
    'Clients',
    'Policies',
    'RegisteredApplications',
    'ODBC',
    'WOW6432Node',
    'Khronos',
    'MozillaPlugins',
    'AppCleaner',
    'app_cleaner',
  };

  /// Scans all installed Windows applications (Win32 Registry + MSIX/Appx).
  Future<List<InstalledApp>> scanInstalledApps() async {
    final apps = <InstalledApp>[];
    final seenNames = <String>{};

    const psScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
function Get-IconBase64($iconPath) {
  if ([string]::IsNullOrWhiteSpace($iconPath)) { return '' }
  $clean = $iconPath.Split(',')[0].Trim().Trim('"')
  if (-not (Test-Path $clean)) { return '' }
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($clean)
    if ($null -eq $ico) { return '' }
    $bmp = $ico.ToBitmap()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $b64 = [Convert]::ToBase64String($ms.ToArray())
    $ms.Dispose(); $bmp.Dispose(); $ico.Dispose()
    return $b64
  } catch { return '' }
}
$paths = @(
  @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'HKLM' },
  @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'HKLM' },
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'HKCU' }
)
$results = @()
foreach ($entry in $paths) {
  Get-ItemProperty $entry.Path | Where-Object { $_.DisplayName } | ForEach-Object {
    $results += [PSCustomObject]@{
      Name = [string]$_.DisplayName
      Id = [string]$_.PSChildName
      Version = [string]$_.DisplayVersion
      Publisher = [string]$_.Publisher
      InstallLocation = [string]$_.InstallLocation
      DisplayIcon = [string]$_.DisplayIcon
      IconBase64 = (Get-IconBase64 ([string]$_.DisplayIcon))
      UninstallString = [string]$_.UninstallString
      SystemComponent = [int]($_.SystemComponent -as [int])
      Scope = $entry.Scope
      Kind = 'Win32'
    }
  }
}
Get-AppxPackage | Where-Object { -not $_.IsFramework } | ForEach-Object {
  $results += [PSCustomObject]@{
    Name = [string]$_.Name
    Id = [string]$_.PackageFamilyName
    Version = [string]$_.Version
    Publisher = [string]$_.Publisher
    InstallLocation = [string]$_.InstallLocation
    DisplayIcon = ''
    IconBase64 = ''
    UninstallString = [string]$_.PackageFullName
    SystemComponent = [int]($_.NonRemovable -or ($_.SignatureKind -eq 'System'))
    Scope = 'Appx'
    Kind = 'Appx'
  }
}
$results | ConvertTo-Json -Compress
''';

    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        psScript,
      ]);
      if (res.exitCode == 0) {
        final stdoutStr = (res.stdout as String).trim();
        if (stdoutStr.isNotEmpty) {
          final decoded = jsonDecode(stdoutStr);
          final list = decoded is List ? decoded : [decoded];
          for (final raw in list) {
            if (raw is! Map) continue;
            final name = (raw['Name']?.toString() ?? '').trim();
            if (name.isEmpty) continue;
            if (!seenNames.add(name.toLowerCase())) continue;

            final id = (raw['Id']?.toString() ?? name).trim();
            final version = (raw['Version']?.toString() ?? '').trim();
            final publisher = (raw['Publisher']?.toString() ?? '').trim();
            final installLocation =
                (raw['InstallLocation']?.toString() ?? '').trim();
            final uninstallStr =
                (raw['UninstallString']?.toString() ?? '').trim();
            final sysComp = (raw['SystemComponent'] as int?) ?? 0;
            final kind = raw['Kind']?.toString() ?? 'Win32';
            final scope = raw['Scope']?.toString() ?? 'HKLM';

            final isSystem = sysComp == 1 ||
                (publisher.contains('Microsoft') &&
                    (name.contains('Redistributable') ||
                        name.contains('Runtime') ||
                        name.contains('.NET') ||
                        name.contains('SDK') ||
                        name.contains('Driver') ||
                        scope == 'Appx' &&
                            id.startsWith('Microsoft.Windows.')));

            int sizeBytes = 0;
            if (installLocation.isNotEmpty &&
                await Directory(installLocation).exists()) {
              sizeBytes = await IoFileUtils.calculateEntitySize(
                installLocation,
                maxFiles: 1500,
              );
            }

            final isSelf = IoFileUtils.isSelfApplication(
              installPath: installLocation,
              identifier: id,
              name: name,
            );

            Uint8List? iconBytes;
            final iconB64 = (raw['IconBase64']?.toString() ?? '').trim();
            if (!isSelf && iconB64.isNotEmpty) {
              try {
                iconBytes = base64Decode(iconB64);
              } catch (_) {}
            }

            apps.add(
              InstalledApp(
                id: '$kind:$id',
                name: name,
                identifier: id,
                version: version,
                publisher: publisher,
                installPath: installLocation,
                origin: isSystem
                    ? AppOriginType.systemApp
                    : AppOriginType.userInstalled,
                installSource: kind == 'Appx'
                    ? InstallSource.msixAppx
                    : InstallSource.win32Registry,
                platform: DesktopPlatformType.windows,
                appSizeBytes: sizeBytes,
                uninstallCommandHint: uninstallStr,
                isSelfApp: isSelf,
                iconBytes: iconBytes,
                isRunning: isSelf,
              ),
            );
          }
        }
      }
    } catch (_) {}

    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  /// Scans %APPDATA%, %LOCALAPPDATA%, %LOCALAPPDATA%\Packages, %PROGRAMDATA%,
  /// and Windows Registry keys (HKCU\Software, HKLM\Software) for [app].
  Future<List<AppDataItem>> scanAppDataItems(InstalledApp app) async {
    final items = <AppDataItem>[];
    final seenPaths = <String>{};

    // 1. MSIX / UWP Package container in %LOCALAPPDATA%\Packages\<PackageFamilyName>
    if (app.installSource == InstallSource.msixAppx) {
      final pkgBase = FormatUtils.joinPath([
        _appDataLocal,
        'Packages',
        app.identifier,
      ]);
      if (await Directory(pkgBase).exists()) {
        final subFolders = <({
          String name,
          DataCategory category,
          String desc,
        })>[
          (
            name: 'LocalCache',
            category: DataCategory.cache,
            desc: 'MSIX package local cache (LocalCache)',
          ),
          (
            name: 'TempState',
            category: DataCategory.cache,
            desc: 'MSIX package temporary state files (TempState)',
          ),
          (
            name: 'LocalState',
            category: DataCategory.appData,
            desc: 'MSIX package local user data (LocalState)',
          ),
          (
            name: 'RoamingState',
            category: DataCategory.preferences,
            desc: 'MSIX package roaming configuration (RoamingState)',
          ),
          (
            name: 'Settings',
            category: DataCategory.preferences,
            desc: 'MSIX package settings store (Settings)',
          ),
        ];

        for (final sub in subFolders) {
          final p = FormatUtils.joinPath([pkgBase, sub.name]);
          if (await Directory(p).exists() && seenPaths.add(p)) {
            items.add(
              AppDataItem(
                id: p,
                name: '${app.name} (${sub.name})',
                path: p,
                category: sub.category,
                sizeBytes: await IoFileUtils.calculateEntitySize(p),
                lastModified: await IoFileUtils.getLastModified(p),
                description: sub.desc,
              ),
            );
          }
        }
      }
    }

    // 2. Standard %APPDATA% (Roaming), %LOCALAPPDATA% (Local), %PROGRAMDATA%
    final tokens = <String>{
      if (app.name.length >= 3) app.name,
      if (app.identifier.length >= 3) app.identifier,
      if (app.installPath.isNotEmpty &&
          FormatUtils.basename(app.installPath).length >= 3)
        FormatUtils.basename(app.installPath),
    };
    final normTokens = tokens
        .map(FormatUtils.normalizeToken)
        .where((t) => t.length >= 3)
        .toSet();

    final searchDirs = <({
      String path,
      DataCategory category,
      String desc,
    })>[
      (
        path: _appDataRoaming,
        category: DataCategory.preferences,
        desc: 'Windows Roaming AppData configuration & data (%APPDATA%)',
      ),
      (
        path: _appDataLocal,
        category: DataCategory.cache,
        desc: 'Windows Local AppData cache & data (%LOCALAPPDATA%)',
      ),
      (
        path: _programData,
        category: DataCategory.appData,
        desc: 'Windows ProgramData shared application data (%PROGRAMDATA%)',
      ),
    ];

    for (final s in searchDirs) {
      final dir = Directory(s.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        final normBase = FormatUtils.normalizeToken(base);
        if (normBase.length >= 3 &&
            normTokens.contains(normBase) &&
            seenPaths.add(entry.path)) {
          final size = await IoFileUtils.calculateEntitySize(entry.path);
          final stat = await FileStat.stat(entry.path);
          items.add(
            AppDataItem(
              id: entry.path,
              name: base,
              path: entry.path,
              category: s.category,
              sizeBytes: size,
              lastModified: stat.modified,
              isDirectory: stat.type == FileSystemEntityType.directory,
              description: s.desc,
            ),
          );
        }
      }
    }

    // 3. Scan Associated Windows Registry Keys (HKCU\Software, HKLM\Software, WOW6432Node)
    final registryItems = await _scanAppRegistryKeys(app, normTokens);
    for (final regItem in registryItems) {
      if (seenPaths.add(regItem.path)) {
        items.add(regItem);
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  /// Discovers Windows Registry keys in HKCU\Software and HKLM\Software belonging to [app].
  Future<List<AppDataItem>> _scanAppRegistryKeys(
    InstalledApp app,
    Set<String> normTokens,
  ) async {
    final results = <AppDataItem>[];
    final candidateKeys = <({String keyPath, String description})>[];

    final cleanName = app.name.split('(').first.trim();
    final cleanPub = app.publisher
        .replaceAll(
          RegExp(r'\b(Inc\.?|Corp\.?|LLC|Ltd\.?|Corporation)\b',
              caseSensitive: false),
          '',
        )
        .trim();

    if (cleanName.isNotEmpty) {
      candidateKeys.add((
        keyPath: 'HKCU\\Software\\$cleanName',
        description: 'Current User Registry configuration & settings (HKCU)',
      ));
      candidateKeys.add((
        keyPath: 'HKLM\\Software\\$cleanName',
        description: 'Local Machine Registry configuration (HKLM)',
      ));
      candidateKeys.add((
        keyPath: 'HKLM\\Software\\WOW6432Node\\$cleanName',
        description: '32-bit Application Registry configuration (WOW6432Node)',
      ));
    }

    if (cleanPub.isNotEmpty &&
        cleanPub.toLowerCase() != 'microsoft' &&
        cleanName.isNotEmpty) {
      candidateKeys.add((
        keyPath: 'HKCU\\Software\\$cleanPub\\$cleanName',
        description: 'Current User Vendor Registry hive (HKCU)',
      ));
      candidateKeys.add((
        keyPath: 'HKLM\\Software\\$cleanPub\\$cleanName',
        description: 'Local Machine Vendor Registry hive (HKLM)',
      ));
    }

    // Also check top-level subkeys of HKCU\Software matching normalized tokens
    try {
      final res = await Process.run('reg', ['query', r'HKCU\Software']);
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith(r'HKEY_CURRENT_USER\Software\')) {
            final sub =
                trimmed.substring(r'HKEY_CURRENT_USER\Software\'.length);
            if (!sub.contains(r'\')) {
              final norm = FormatUtils.normalizeToken(sub);
              if (norm.length >= 3 && normTokens.contains(norm)) {
                candidateKeys.add((
                  keyPath: 'HKCU\\Software\\$sub',
                  description:
                      'Current User Registry key matched by application token',
                ));
              }
            }
          }
        }
      }
    } catch (_) {}

    final checked = <String>{};
    for (final candidate in candidateKeys) {
      if (!checked.add(candidate.keyPath.toLowerCase())) continue;
      final regInfo = await _inspectRegistryKey(candidate.keyPath);
      if (regInfo.exists) {
        results.add(
          AppDataItem(
            id: 'reg:${candidate.keyPath}',
            name: FormatUtils.basename(candidate.keyPath),
            path: candidate.keyPath,
            category: DataCategory.registry,
            sizeBytes: regInfo.estimatedBytes,
            isDirectory: false,
            description:
                '${candidate.description} (${regInfo.valueCount} values/subkeys)',
          ),
        );
      }
    }

    return results;
  }

  Future<({bool exists, int estimatedBytes, int valueCount})>
      _inspectRegistryKey(String keyPath) async {
    try {
      final res = await Process.run('reg', ['query', keyPath, '/s']);
      if (res.exitCode == 0) {
        final output = res.stdout as String;
        final lines = output
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        return (
          exists: true,
          estimatedBytes: output.length.clamp(512, 10 * 1024 * 1024),
          valueCount: lines.length,
        );
      }
    } catch (_) {}
    return (exists: false, estimatedBytes: 0, valueCount: 0);
  }

  /// Exports a backup `.reg` file before deleting a Windows Registry key (`reg delete <keyPath> /f`).
  /// Falls back to UAC administrator elevation if an HKLM key requires elevated permissions.
  Future<bool> deleteRegistryKey(
    String keyPath, {
    List<String>? logs,
  }) async {
    if (!PlatformParsers.isSafeWindowsRegistryKeyPath(keyPath)) {
      logs?.add('Blocked deletion of protected system Registry path: $keyPath');
      return false;
    }
    try {
      // 1. Export safe backup to %TEMP%\AppCleaner_RegistryBackups
      final tempDir = Platform.environment['TEMP'] ?? r'C:\Windows\Temp';
      final backupDir = Directory('$tempDir\\AppCleaner_RegistryBackups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final safeFileName = keyPath
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .toLowerCase();
      final backupFile =
          '${backupDir.path}\\${DateTime.now().millisecondsSinceEpoch}_$safeFileName.reg';
      final exportRes = await Process.run(
        'reg',
        ['export', keyPath, backupFile, '/y'],
      );
      if (exportRes.exitCode == 0) {
        logs?.add('Backed up registry key to: $backupFile');
      }

      // 2. Delete registry key via reg delete <keyPath> /f
      final delRes = await Process.run('reg', ['delete', keyPath, '/f']);
      if (delRes.exitCode == 0) {
        logs?.add('Deleted registry key: $keyPath');
        return true;
      }

      // 3. If HKLM requires Administrator privileges, request UAC elevation via PowerShell
      if (keyPath.toUpperCase().startsWith('HKLM') ||
          keyPath.toUpperCase().startsWith('HKEY_LOCAL_MACHINE')) {
        final psElevate =
            'Start-Process reg -ArgumentList \'delete "$keyPath" /f\' -Verb RunAs -Wait';
        final elevRes = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          psElevate,
        ]);
        if (elevRes.exitCode == 0) {
          logs?.add('Deleted HKLM registry key with Administrator UAC: $keyPath');
          return true;
        }
      }
    } catch (e) {
      logs?.add('Failed to delete registry key $keyPath: $e');
    }
    return false;
  }

  /// Scans %APPDATA%, %LOCALAPPDATA%, and HKCU\Software for orphaned folders
  /// and orphaned Windows Registry keys left behind by uninstalled apps.
  Future<List<OrphanLeftoverGroup>> scanOrphanedLeftovers(
    List<InstalledApp> installedApps,
  ) async {
    final installedNorms = <String>{};
    for (final app in installedApps) {
      for (final raw in [
        app.name,
        app.identifier,
        app.publisher,
        FormatUtils.basename(app.installPath),
      ]) {
        final norm = FormatUtils.normalizeToken(raw);
        if (norm.length >= 2) installedNorms.add(norm);
      }
    }

    final targets = <({String path, DataCategory category})>[
      (path: _appDataRoaming, category: DataCategory.preferences),
      (path: _appDataLocal, category: DataCategory.cache),
    ];

    final grouped = <String, List<AppDataItem>>{};
    final titles = <String, String>{};

    // 1. Scan file system leftovers in %APPDATA% and %LOCALAPPDATA%
    for (final t in targets) {
      final dir = Directory(t.path);
      if (!await dir.exists()) continue;

      List<FileSystemEntity> entries = [];
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        final base = FormatUtils.basename(entry.path);
        if (base.startsWith('.') ||
            _ignoredWindowsOrphanDirs.contains(base)) {
          continue;
        }
        final norm = FormatUtils.normalizeToken(base);
        if (norm.length < 3 || installedNorms.contains(norm)) continue;

        final size = await IoFileUtils.calculateEntitySize(
          entry.path,
          maxFiles: 1500,
        );
        if (size == 0) continue;

        final stat = await FileStat.stat(entry.path);
        titles.putIfAbsent(norm, () => base);
        grouped.putIfAbsent(norm, () => []).add(
              AppDataItem(
                id: entry.path,
                name: base,
                path: entry.path,
                category: t.category,
                sizeBytes: size,
                lastModified: stat.modified,
                isDirectory: stat.type == FileSystemEntityType.directory,
                description:
                    'Orphaned directory not matching any installed Windows program',
                selected: false,
              ),
            );
      }
    }

    // 2. Scan HKCU\Software for orphaned registry keys
    try {
      final res = await Process.run('reg', ['query', r'HKCU\Software']);
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith(r'HKEY_CURRENT_USER\Software\')) continue;
          final sub = trimmed.substring(r'HKEY_CURRENT_USER\Software\'.length);
          if (sub.isEmpty ||
              sub.contains(r'\') ||
              _ignoredWindowsOrphanDirs.contains(sub)) {
            continue;
          }
          final norm = FormatUtils.normalizeToken(sub);
          if (norm.length < 3 || installedNorms.contains(norm)) continue;

          final keyPath = 'HKCU\\Software\\$sub';
          final info = await _inspectRegistryKey(keyPath);
          if (!info.exists || info.valueCount <= 1) continue;

          titles.putIfAbsent(norm, () => sub);
          grouped.putIfAbsent(norm, () => []).add(
                AppDataItem(
                  id: 'reg:$keyPath',
                  name: '$sub (Registry Key)',
                  path: keyPath,
                  category: DataCategory.registry,
                  sizeBytes: info.estimatedBytes,
                  isDirectory: false,
                  description:
                      'Orphaned Windows Registry hive in HKCU\\Software (${info.valueCount} entries)',
                  selected: false,
                ),
              );
        }
      }
    } catch (_) {}

    final groups = <OrphanLeftoverGroup>[];
    grouped.forEach((key, list) {
      groups.add(
        OrphanLeftoverGroup(
          id: key,
          suspectedAppName: titles[key] ?? key,
          identifier: key,
          platform: DesktopPlatformType.windows,
          confidenceReason:
              'Not found in Windows Uninstall Registry keys or MSIX packages',
          items: list,
        ),
      );
    });
    groups.sort((a, b) => b.totalSizeBytes.compareTo(a.totalSizeBytes));
    return groups;
  }
}
