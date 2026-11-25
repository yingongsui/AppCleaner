import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'models/app_models.dart';
import 'services/app_cleaner_service.dart';
import 'utils/format_utils.dart';
import 'widgets/app_detail_panel.dart';
import 'widgets/orphan_leftovers_view.dart';
import 'widgets/settings_view.dart';
import 'widgets/shared_badges.dart';
import 'widgets/uninstall_confirm_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppCleanerApp());
}

/// Top-level navigation section in AppCleaner.
enum NavigationSection {
  apps,
  orphanLeftovers,
  operationLogs,
  settings;
}

/// Filter for User Installed Apps vs System Apps.
enum AppOriginFilter {
  all,
  userOnly,
  systemOnly;

  String get label {
    switch (this) {
      case AppOriginFilter.all:
        return 'All';
      case AppOriginFilter.userOnly:
        return 'User Apps';
      case AppOriginFilter.systemOnly:
        return 'System Apps';
    }
  }
}

/// Sort order for the application list.
enum AppSortField {
  name,
  appSize,
  dataSize,
  totalSize;

  String get label {
    switch (this) {
      case AppSortField.name:
        return 'Sort by Name';
      case AppSortField.appSize:
        return 'Sort by App Size';
      case AppSortField.dataSize:
        return 'Sort by Data & Cache';
      case AppSortField.totalSize:
        return 'Sort by Total Footprint';
    }
  }
}

class AppCleanerApp extends StatelessWidget {
  final AppCleanerService? service;

  const AppCleanerApp({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppCleaner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: AppCleanerHomePage(service: service),
    );
  }
}

class AppCleanerHomePage extends StatefulWidget {
  final AppCleanerService? service;

  const AppCleanerHomePage({super.key, this.service});

  @override
  State<AppCleanerHomePage> createState() => _AppCleanerHomePageState();
}

class _AppCleanerHomePageState extends State<AppCleanerHomePage> {
  late final AppCleanerService _service;

  NavigationSection _currentSection = NavigationSection.apps;
  AppOriginFilter _originFilter = AppOriginFilter.userOnly;
  AppSortField _sortField = AppSortField.name;
  String _searchQuery = '';
  final TextEditingController _appSearchController = TextEditingController();

  List<InstalledApp> _apps = [];
  InstalledApp? _selectedApp;
  List<OrphanLeftoverGroup> _orphanGroups = [];
  final List<OperationLogEntry> _operationLogs = [];
  AppCleanerSettings _settings = const AppCleanerSettings();

  bool _isScanningApps = false;
  bool _isScanningSelectedAppData = false;
  bool _isBatchScanningAllData = false;
  int _batchScannedCount = 0;
  bool _isScanningOrphans = false;
  DesktopPlatformType? _webDebugPlatformFilter;
  int _totalFreedSessionBytes = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppCleanerService();
    _loadStartupState();
  }

  @override
  void dispose() {
    _appSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadStartupState() async {
    final loadedSettings = await _service.loadSettings();
    if (mounted) {
      setState(() {
        _settings = loadedSettings;
        if (loadedSettings.includeSystemAppsByDefault) {
          _originFilter = AppOriginFilter.all;
        }
      });
    }
    _loadPersistedHistory();
    await _loadInitialScan();
  }

  void _handleUpdateSettings(AppCleanerSettings nextSettings) {
    final prevSubfolder = _settings.scanVendorSubfolders;
    final prevWhitelistLen = _settings.customWhitelist.length;
    final prevAssocLen = _settings.customAssociations.length;
    setState(() {
      _settings = nextSettings;
      if (prevSubfolder != nextSettings.scanVendorSubfolders ||
          prevWhitelistLen != nextSettings.customWhitelist.length ||
          prevAssocLen != nextSettings.customAssociations.length) {
        for (final app in _apps) {
          app.dataScanned = false;
        }
      }
    });
    _service.saveSettings(nextSettings);
    if (_selectedApp != null && !_selectedApp!.dataScanned) {
      _selectApp(_selectedApp!, forceRescan: true);
    }
  }

  void _handleAssociateOrphanWithApp(
    OrphanLeftoverGroup group,
    InstalledApp targetApp, {
    AppDataItem? singleItem,
  }) {
    final targetItems =
        singleItem != null ? [singleItem] : List<AppDataItem>.from(group.items);
    if (targetItems.isEmpty) return;

    final nextAssocs = List<CustomAppAssociation>.from(
      _settings.customAssociations,
    );
    for (final item in targetItems) {
      nextAssocs.removeWhere(
        (a) => a.path.toLowerCase() == item.path.toLowerCase(),
      );
      nextAssocs.insert(
        0,
        CustomAppAssociation(
          path: item.path,
          label: item.name,
          category: item.category,
          appId: targetApp.id,
          appIdentifier: targetApp.identifier,
          appName: targetApp.name,
        ),
      );
      if (!targetApp.dataItems.any(
        (d) => d.path.toLowerCase() == item.path.toLowerCase(),
      )) {
        targetApp.dataItems.add(
          AppDataItem(
            id: item.id,
            name: item.name,
            path: item.path,
            category: item.category,
            sizeBytes: item.sizeBytes,
            lastModified: item.lastModified,
            isDirectory: item.isDirectory,
            description: 'Manually associated with ${targetApp.name}',
            selected: true,
          ),
        );
      }
    }

    final updatedSettings = _settings.copyWith(customAssociations: nextAssocs);
    setState(() {
      _settings = updatedSettings;
      if (singleItem != null) {
        group.items.remove(singleItem);
        if (group.items.isEmpty) {
          _orphanGroups.remove(group);
        }
      } else {
        _orphanGroups.remove(group);
      }
    });
    _service.saveSettings(updatedSettings);
    _showSnack(
      'Associated "${singleItem?.name ?? group.suspectedAppName}" with ${targetApp.name}.',
      tone: CapsuleToastTone.success,
    );
  }

  void _handleAddOrphanToWhitelist(
    OrphanLeftoverGroup group, {
    AppDataItem? singleItem,
  }) {
    final targetItems =
        singleItem != null ? [singleItem] : List<AppDataItem>.from(group.items);
    if (targetItems.isEmpty) return;

    final nextWhitelist = List<String>.from(_settings.customWhitelist);
    for (final item in targetItems) {
      final exists = nextWhitelist.any(
        (r) => r.toLowerCase() == item.path.toLowerCase(),
      );
      if (!exists) {
        nextWhitelist.insert(0, item.path);
      }
    }

    final updatedSettings = _settings.copyWith(customWhitelist: nextWhitelist);
    setState(() {
      _settings = updatedSettings;
      if (singleItem != null) {
        group.items.remove(singleItem);
        if (group.items.isEmpty) {
          _orphanGroups.remove(group);
        }
      } else {
        _orphanGroups.remove(group);
      }
    });
    _service.saveSettings(updatedSettings);
    _showSnack(
      'Added "${singleItem?.name ?? group.suspectedAppName}" to whitelist.',
      tone: CapsuleToastTone.success,
    );
  }

  Future<void> _loadPersistedHistory() async {
    final saved = await _service.loadOperationHistory();
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _operationLogs
        ..clear()
        ..addAll(saved);
      _totalFreedSessionBytes = saved.fold<int>(
        0,
        (sum, entry) => sum + entry.result.freedBytes,
      );
    });
  }

  Future<void> _handleClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Activity History?'),
        content: const Text(
          'This will remove all saved cleaning and uninstallation log entries from disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _service.clearOperationHistory();
    if (!mounted) return;
    setState(() {
      _operationLogs.clear();
      _totalFreedSessionBytes = 0;
    });
    _showSnack('Activity history cleared.', tone: CapsuleToastTone.success);
  }

  Future<void> _loadInitialScan() async {
    await _scanInstalledApps();
  }

  Future<void> _scanInstalledApps() async {
    if (_isScanningApps) return;
    setState(() {
      _isScanningApps = true;
    });

    try {
      final apps = await _service.scanInstalledApps(
        filterPlatform: _webDebugPlatformFilter,
      );
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _isScanningApps = false;
      });

      final visible = _filteredAndSortedApps;
      if (visible.isNotEmpty) {
        final keepCurrent = _selectedApp != null &&
            visible.any((a) => a.id == _selectedApp!.id);
        await _selectApp(
          keepCurrent
              ? visible.firstWhere((a) => a.id == _selectedApp!.id)
              : visible.first,
        );
      } else {
        setState(() => _selectedApp = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanningApps = false);
    }
  }

  Future<void> _selectApp(InstalledApp app, {bool forceRescan = false}) async {
    setState(() {
      _selectedApp = app;
    });
    if (!app.dataScanned || forceRescan) {
      setState(() => _isScanningSelectedAppData = true);
      try {
        await _service.ensureAppDataScanned(app, settings: _settings);
      } finally {
        if (mounted) {
          setState(() => _isScanningSelectedAppData = false);
        }
      }
    }
  }

  Future<void> _batchScanAllVisibleAppData() async {
    if (_isBatchScanningAllData) return;
    final targets =
        _filteredAndSortedApps.where((a) => !a.dataScanned).toList();
    if (targets.isEmpty) {
      _showSnack('All applications in the current view have already been scanned.');
      return;
    }

    setState(() {
      _isBatchScanningAllData = true;
      _batchScannedCount = 0;
    });

    const batchConcurrency = 4;
    for (var i = 0; i < targets.length; i += batchConcurrency) {
      if (!mounted) return;
      final chunk = targets.sublist(
        i,
        (i + batchConcurrency).clamp(0, targets.length),
      );
      await Future.wait(
        chunk.map((t) => _service.ensureAppDataScanned(t, settings: _settings)),
      );
      if (!mounted) return;
      setState(() {
        _batchScannedCount = (i + chunk.length).clamp(0, targets.length);
      });
    }

    if (mounted) {
      setState(() => _isBatchScanningAllData = false);
      _showSnack(
        'Completed deep data scan for ${targets.length} applications.',
        tone: CapsuleToastTone.success,
      );
    }
  }

  Future<void> _scanOrphanLeftovers() async {
    if (_isScanningOrphans) return;
    setState(() => _isScanningOrphans = true);
    try {
      if (_apps.isEmpty) {
        _apps = await _service.scanInstalledApps(
          filterPlatform: _webDebugPlatformFilter,
        );
      }
      final groups = await _service.scanOrphanedLeftovers(
        _apps,
        settings: _settings,
      );
      // Always start orphaned leftovers deselected so users explicitly opt in.
      for (final group in groups) {
        for (final item in group.items) {
          item.selected = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _orphanGroups = groups;
        _isScanningOrphans = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isScanningOrphans = false);
      }
    }
  }

  Future<void> _handleClearCacheOnly(InstalledApp app) async {
    final cacheBytes = app.cacheSizeBytes;
    if (cacheBytes == 0) return;

    bool moveToTrash = _settings.defaultMoveToTrash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Clear Cache for "${app.name}"?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This will clean runtime cache, logs, and saved session state (${FormatUtils.formatBytes(cacheBytes)}).\n'
                  'Your user accounts, preferences, Registry settings, and the application binary will be preserved.',
                ),
                const SizedBox(height: 14),
                DeletionModeToggle(
                  moveToTrash: moveToTrash,
                  onChanged: (v) => setDialogState(() => moveToTrash = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: moveToTrash
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                    ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                moveToTrash ? 'Clear Cache (Move to Trash)' : 'Clear Cache Permanently',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _service.clearAppData(
      app: app,
      cacheOnly: true,
      onlySelected: false,
      moveToTrash: moveToTrash,
    );
    _recordOperation('Clear Cache: ${app.name}', res);
  }

  Future<void> _handleClearAllData(InstalledApp app) async {
    final selectedBytes = app.selectedDataSizeBytes;
    final selectedCount = app.dataItems.where((d) => d.selected).length;
    if (selectedCount == 0) return;

    bool moveToTrash = _settings.defaultMoveToTrash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(
            Icons.restart_alt_rounded,
            color: Colors.teal,
            size: 36,
          ),
          title: Text('Reset App Data for "${app.name}"?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This will remove the $selectedCount selected data, configuration, sandbox container, cache, and Registry items (${FormatUtils.formatBytes(selectedBytes)}).\n\n'
                  '• The application binary (${app.installPath}) will NOT be uninstalled.\n'
                  '• Next time you launch the app, it will start in a clean, freshly-installed state.',
                ),
                const SizedBox(height: 14),
                DeletionModeToggle(
                  moveToTrash: moveToTrash,
                  onChanged: (v) => setDialogState(() => moveToTrash = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: moveToTrash
                    ? Colors.teal.shade700
                    : Theme.of(ctx).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                moveToTrash
                    ? 'Move to Trash (${FormatUtils.formatBytes(selectedBytes)})'
                    : 'Delete Permanently (${FormatUtils.formatBytes(selectedBytes)})',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _service.clearAppData(
      app: app,
      cacheOnly: false,
      onlySelected: true,
      moveToTrash: moveToTrash,
    );
    _recordOperation('Reset App Data: ${app.name}', res);
  }

  Future<void> _handleUninstallApp(InstalledApp app) async {
    final choices = await showDialog<UninstallDialogChoices>(
      context: context,
      builder: (ctx) => UninstallConfirmDialog(
        app: app,
        initialMoveToTrash: _settings.defaultMoveToTrash,
      ),
    );
    if (choices == null || !mounted) return;

    final res = await _service.uninstallApp(
      app: app,
      removeSelectedData: choices.removeSelectedData,
      removeSelectedLinuxDeps: choices.removeSelectedLinuxDeps,
      moveToTrash: choices.moveToTrash,
    );

    setState(() {
      if (res.deletedPaths.contains(app.installPath)) {
        _apps.removeWhere((a) => a.id == app.id);
        final remaining = _filteredAndSortedApps;
        _selectedApp = remaining.isNotEmpty ? remaining.first : null;
      }
    });
    if (_selectedApp != null && !_selectedApp!.dataScanned) {
      _selectApp(_selectedApp!);
    }

    _recordOperation('Uninstall App & Leftovers: ${app.name}', res);
  }

  Future<void> _handleCleanSelectedOrphans() async {
    final selectedCount = _orphanGroups.fold<int>(
      0,
      (sum, g) => sum + g.selectedCount,
    );
    final selectedBytes = _orphanGroups.fold<int>(
      0,
      (sum, g) => sum + g.selectedSizeBytes,
    );
    if (selectedCount == 0) return;

    bool moveToTrash = _settings.defaultMoveToTrash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Clean Selected Orphaned Leftovers?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selected $selectedCount orphaned files, directories, or Windows Registry keys (${FormatUtils.formatBytes(selectedBytes)}).',
                ),
                const SizedBox(height: 14),
                DeletionModeToggle(
                  moveToTrash: moveToTrash,
                  onChanged: (v) => setDialogState(() => moveToTrash = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: moveToTrash
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                    ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                moveToTrash ? 'Move to Trash' : 'Delete Permanently',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _service.cleanOrphanLeftovers(
      _orphanGroups,
      moveToTrash: moveToTrash,
    );
    setState(() {
      _orphanGroups.removeWhere((g) => g.items.isEmpty);
    });
    _recordOperation('Clean Orphaned Leftovers', res);
  }

  void _recordOperation(String title, CleanActionResult result) {
    if (!mounted) return;
    setState(() {
      _totalFreedSessionBytes += result.freedBytes;
      _operationLogs.insert(
        0,
        OperationLogEntry(
          timestamp: DateTime.now(),
          title: title,
          result: result,
        ),
      );
    });
    // Persist history immediately to disk so it survives app restarts.
    _service.saveOperationHistory(_operationLogs);
    final tone = !result.success
        ? CapsuleToastTone.error
        : (result.failedPaths.isNotEmpty
            ? CapsuleToastTone.warning
            : CapsuleToastTone.success);
    _showSnack(result.summaryMessage, tone: tone);
  }

  void _showSnack(
    String message, {
    CapsuleToastTone tone = CapsuleToastTone.info,
  }) {
    if (!mounted) return;
    showCapsuleToast(context, message, tone: tone);
  }

  List<InstalledApp> get _filteredAndSortedApps {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _apps.where((app) {
      if (_originFilter == AppOriginFilter.userOnly && app.isSystemApp) {
        return false;
      }
      if (_originFilter == AppOriginFilter.systemOnly && !app.isSystemApp) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchName = app.name.toLowerCase().contains(q);
        final matchId = app.identifier.toLowerCase().contains(q);
        final matchPub = app.publisher.toLowerCase().contains(q);
        final matchPkg =
            app.linuxPackageName?.toLowerCase().contains(q) ?? false;
        if (!matchName && !matchId && !matchPub && !matchPkg) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortField) {
        case AppSortField.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case AppSortField.appSize:
          return b.appSizeBytes.compareTo(a.appSizeBytes);
        case AppSortField.dataSize:
          return b.totalDataSizeBytes.compareTo(a.totalDataSizeBytes);
        case AppSortField.totalSize:
          return b.totalFootprintBytes.compareTo(a.totalFootprintBytes);
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final userAppsCount =
        _apps.where((a) => a.origin == AppOriginType.userInstalled).length;
    final systemAppsCount =
        _apps.where((a) => a.origin == AppOriginType.systemApp).length;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompactRail = constraints.maxWidth < 1080;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCompactRail)
                _buildCompactRail(
                  context,
                  userAppsCount: userAppsCount,
                  systemAppsCount: systemAppsCount,
                )
              else
                _buildFullSidebar(
                  context,
                  theme: theme,
                  colorScheme: colorScheme,
                  userAppsCount: userAppsCount,
                  systemAppsCount: systemAppsCount,
                ),

              // Main Content Area
              Expanded(
                child: _buildActiveSectionContent(
                  context,
                  userAppsCount: userAppsCount,
                  systemAppsCount: systemAppsCount,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFullSidebar(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int userAppsCount,
    required int systemAppsCount,
  }) {
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 42,
                    height: 42,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AppCleaner',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        kIsWeb
                            ? 'Cross-Platform Web UI'
                            : '${DesktopPlatformType.current.label} Uninstaller & Cleaner',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Navigation buttons
          _buildSidebarNavItem(
            section: NavigationSection.apps,
            icon: Icons.apps_rounded,
            title: 'Installed Apps',
            subtitle: 'User $userAppsCount · System $systemAppsCount',
          ),
          _buildSidebarNavItem(
            section: NavigationSection.orphanLeftovers,
            icon: Icons.auto_delete_rounded,
            title: 'Orphaned Leftovers',
            subtitle: _orphanGroups.isEmpty
                ? 'Scan files & Registry keys'
                : '${_orphanGroups.length} leftover groups found',
            onTapExtra: () {
              if (_settings.autoScanOrphansOnOpen &&
                  _orphanGroups.isEmpty &&
                  !_isScanningOrphans) {
                _scanOrphanLeftovers();
              }
            },
          ),
          _buildSidebarNavItem(
            section: NavigationSection.operationLogs,
            icon: Icons.history_rounded,
            title: 'Activity History',
            subtitle:
                'Freed ${FormatUtils.formatBytes(_totalFreedSessionBytes)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Divider(height: 1),
          ),
          _buildSidebarNavItem(
            section: NavigationSection.settings,
            icon: Icons.settings_rounded,
            title: 'Settings',
            subtitle: 'Scan depth, whitelist & about',
          ),

          const Spacer(),

          // Web UI Debug Platform Switcher (when running on Chrome / Web Server)
          if (kIsWeb)
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.web_rounded,
                        size: 16,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Web UI Debug Mode',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Preview platform workflows in browser:',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text(
                          'All OS',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _webDebugPlatformFilter == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() => _webDebugPlatformFilter = null);
                          _scanInstalledApps();
                        },
                      ),
                      ...DesktopPlatformType.values.map(
                        (p) => ChoiceChip(
                          label: Text(
                            p.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _webDebugPlatformFilter == p,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _webDebugPlatformFilter = p);
                            _scanInstalledApps();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Total Freed Space Card
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Space Freed',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  FormatUtils.formatBytes(_totalFreedSessionBytes),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRail(
    BuildContext context, {
    required int userAppsCount,
    required int systemAppsCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 14),
            child: Tooltip(
              message: 'AppCleaner',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 36,
                  height: 36,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildCompactRailItem(
            section: NavigationSection.apps,
            icon: Icons.apps_rounded,
            tooltip:
                'Installed Apps (User $userAppsCount · System $systemAppsCount)',
          ),
          _buildCompactRailItem(
            section: NavigationSection.orphanLeftovers,
            icon: Icons.auto_delete_rounded,
            tooltip: 'Orphaned Leftovers',
            onTapExtra: () {
              if (_settings.autoScanOrphansOnOpen &&
                  _orphanGroups.isEmpty &&
                  !_isScanningOrphans) {
                _scanOrphanLeftovers();
              }
            },
          ),
          _buildCompactRailItem(
            section: NavigationSection.operationLogs,
            icon: Icons.history_rounded,
            tooltip:
                'Activity History (Freed ${FormatUtils.formatBytes(_totalFreedSessionBytes)})',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Divider(height: 1),
          ),
          _buildCompactRailItem(
            section: NavigationSection.settings,
            icon: Icons.settings_rounded,
            tooltip: 'Settings & Whitelist',
          ),
          const Spacer(),
          Tooltip(
            message:
                'Total Space Freed: ${FormatUtils.formatBytes(_totalFreedSessionBytes)}',
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cleaning_services_rounded,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    FormatUtils.formatBytes(_totalFreedSessionBytes),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRailItem({
    required NavigationSection section,
    required IconData icon,
    required String tooltip,
    VoidCallback? onTapExtra,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _currentSection == section;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _currentSection = section);
            onTapExtra?.call();
          },
          child: Container(
            width: 48,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: selected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required NavigationSection section,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTapExtra,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _currentSection == section;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _currentSection = section);
          onTapExtra?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13.5,
                        color: selected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? colorScheme.onSecondaryContainer
                                .withValues(alpha: 0.8)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSectionContent(
    BuildContext context, {
    required int userAppsCount,
    required int systemAppsCount,
  }) {
    switch (_currentSection) {
      case NavigationSection.apps:
        return _buildAppsSplitView(
          context,
          userAppsCount: userAppsCount,
          systemAppsCount: systemAppsCount,
        );
      case NavigationSection.orphanLeftovers:
        return OrphanLeftoversView(
          orphanGroups: _orphanGroups,
          installedApps: _apps,
          isScanning: _isScanningOrphans,
          expandCardsByDefault: _settings.expandOrphanCardsByDefault,
          onRescan: _scanOrphanLeftovers,
          onCleanSelected: _handleCleanSelectedOrphans,
          onRevealPath: _service.revealInFileManager,
          onSelectionChanged: () => setState(() {}),
          onAssociateWithApp: _handleAssociateOrphanWithApp,
          onAddToWhitelist: _handleAddOrphanToWhitelist,
        );
      case NavigationSection.operationLogs:
        return _buildOperationLogsView(context);
      case NavigationSection.settings:
        return SettingsView(
          settings: _settings,
          builtInWhitelist: _service.getBuiltInWhitelist(),
          configDirectoryPath: _service.getConfigDirectoryPath(),
          onUpdateSettings: _handleUpdateSettings,
          onRevealPath: _service.revealInFileManager,
        );
    }
  }

  Widget _buildFilterSegmentLabel(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$count',
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsSplitView(
    BuildContext context, {
    required int userAppsCount,
    required int systemAppsCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleApps = _filteredAndSortedApps;

    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = (constraints.maxWidth * 0.36).clamp(276.0, 380.0);
        final headerPad = listWidth < 330 ? 12.0 : 16.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Master List of Installed Apps
            Container(
              width: listWidth,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  right: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filter & Search Header
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      headerPad,
                      14,
                      headerPad,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Segmented Filter: User Apps vs System Apps vs All
                        // Uniform 2-line layout (title on top, count below)
                        SegmentedButton<AppOriginFilter>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            padding: WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            ButtonSegment(
                              value: AppOriginFilter.userOnly,
                              label: _buildFilterSegmentLabel(
                                'User Apps',
                                userAppsCount,
                              ),
                            ),
                            ButtonSegment(
                              value: AppOriginFilter.systemOnly,
                              label: _buildFilterSegmentLabel(
                                'System Apps',
                                systemAppsCount,
                              ),
                            ),
                            ButtonSegment(
                              value: AppOriginFilter.all,
                              label: _buildFilterSegmentLabel(
                                'All',
                                _apps.length,
                              ),
                            ),
                          ],
                          selected: {_originFilter},
                          onSelectionChanged: (set) {
                            setState(() {
                              _originFilter = set.first;
                              final updated = _filteredAndSortedApps;
                              if (updated.isNotEmpty &&
                                  (_selectedApp == null ||
                                      !updated.any(
                                        (a) => a.id == _selectedApp!.id,
                                      ))) {
                                _selectApp(updated.first);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 10),

                        // Search Bar
                        TextField(
                          controller: _appSearchController,
                          decoration: InputDecoration(
                            hintText:
                                'Search by app name, Bundle ID, or package...',
                            prefixIcon: const Icon(Icons.search, size: 19),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear Search',
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                    ),
                                    onPressed: () {
                                      _appSearchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                            isDense: true,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                        const SizedBox(height: 8),

                        // Sort Menu + Batch Deep Scan + Refresh
                        Row(
                          children: [
                            Flexible(
                              child: PopupMenuButton<AppSortField>(
                                initialValue: _sortField,
                                onSelected: (field) =>
                                    setState(() => _sortField = field),
                                itemBuilder: (ctx) => AppSortField.values
                                    .map(
                                      (f) => PopupMenuItem(
                                        value: f,
                                        child: Text(f.label),
                                      ),
                                    )
                                    .toList(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sort_rounded, size: 15),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          _sortField.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 11.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed:
                                  _isBatchScanningAllData || _isScanningApps
                                      ? null
                                      : _batchScanAllVisibleAppData,
                              icon: _isBatchScanningAllData
                                  ? const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.radar_rounded, size: 15),
                              label: Text(
                                _isBatchScanningAllData
                                    ? 'Scan ($_batchScannedCount)'
                                    : 'Scan Sizes',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Refresh Installed Apps',
                              onPressed:
                                  _isScanningApps ? null : _scanInstalledApps,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // App List
                  Expanded(
                    child: _isScanningApps
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text('Scanning installed applications...'),
                              ],
                            ),
                          )
                        : visibleApps.isEmpty
                            ? Center(
                                child: Text(
                                  'No matching applications found',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: visibleApps.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final app = visibleApps[index];
                                  final isSelected = _selectedApp?.id == app.id;
                                  return _buildAppListItem(
                                    context,
                                    app,
                                    isSelected,
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),

            // Right Detail Pane (top-aligned via stretch + SizedBox.expand)
            Expanded(
              child: _selectedApp == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Select an application on the left to inspect storage, reset data, or uninstall',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : AppDetailPanel(
                      app: _selectedApp!,
                      isScanningData: _isScanningSelectedAppData,
                      onRescanAppData: () =>
                          _selectApp(_selectedApp!, forceRescan: true),
                      onClearCacheOnly: () =>
                          _handleClearCacheOnly(_selectedApp!),
                      onClearAllData: () => _handleClearAllData(_selectedApp!),
                      onUninstallApp: () => _handleUninstallApp(_selectedApp!),
                      onTerminateProcess: () async {
                        final ok =
                            await _service.terminateRunningApp(_selectedApp!);
                        if (ok && mounted) {
                          setState(() => _selectedApp!.isRunning = false);
                          _showSnack(
                            'Terminated running process: ${_selectedApp!.name}',
                            tone: CapsuleToastTone.success,
                          );
                        }
                      },
                      onRevealPath: _service.revealInFileManager,
                      onSelectionChanged: () => setState(() {}),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppListItem(
    BuildContext context,
    InstalledApp app,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isSystem = app.isSystemApp;

    return InkWell(
      onTap: () => _selectApp(app),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        child: Row(
          children: [
            AppAvatar(
              name: app.name,
              isSystem: isSystem,
              isSelfApp: app.isSelfApp,
              iconBytes: app.iconBytes,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (app.isSelfApp)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: isDark
                                ? Colors.lightBlue.shade200
                                : Colors.blue.shade700,
                          ),
                        ),
                      if (app.isRunning)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  LayoutBuilder(
                    builder: (context, subConstraints) {
                      final maxBadgeWidth =
                          (subConstraints.maxWidth * 0.65).clamp(40.0, 96.0);
                      return Row(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxBadgeWidth,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: app.isSelfApp
                                    ? Colors.blue
                                        .withValues(alpha: isDark ? 0.28 : 0.16)
                                    : (isSystem
                                        ? Colors.amber.withValues(
                                            alpha: isDark ? 0.24 : 0.2,
                                          )
                                        : Colors.indigo.withValues(
                                            alpha: isDark ? 0.28 : 0.14,
                                          )),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                app.isSelfApp
                                    ? 'Self-Locked'
                                    : app.origin.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: app.isSelfApp
                                      ? (isDark
                                          ? Colors.lightBlue.shade200
                                          : Colors.blue.shade800)
                                      : (isSystem
                                          ? (isDark
                                              ? Colors.amber.shade300
                                              : Colors.amber.shade900)
                                          : (isDark
                                              ? Colors.indigo.shade200
                                              : Colors.indigo.shade800)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${app.platform.label} · ${app.installSource.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FormatUtils.formatBytes(app.appSizeBytes),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                if (app.dataScanned)
                  Text(
                    'Data: ${FormatUtils.formatBytes(app.totalDataSizeBytes)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: app.totalDataSizeBytes > 0
                          ? Colors.teal.shade700
                          : colorScheme.onSurfaceVariant,
                      fontWeight: app.totalDataSizeBytes > 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationLogsView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_operationLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 60,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No Cleaning or Uninstallation History Yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Detailed logs will appear here after you Clear Cache, Reset App Data, Uninstall an App, or Clean Orphaned Leftovers.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;
            final headerInfo = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.history_rounded, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity History (${_operationLogs.length} entries)',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Automatically saved to disk · Cumulative space freed: ${FormatUtils.formatBytes(_totalFreedSessionBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final clearBtn = OutlinedButton.icon(
              onPressed: _handleClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear History'),
            );

            return Container(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 24,
                18,
                isCompact ? 16 : 24,
                14,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headerInfo,
                        const SizedBox(height: 10),
                        clearBtn,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: headerInfo),
                        const SizedBox(width: 12),
                        clearBtn,
                      ],
                    ),
            );
          },
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: _operationLogs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = _operationLogs[index];
              final res = entry.result;
              return Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            res.success
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            color: res.success ? Colors.teal : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            FormatUtils.formatDate(entry.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(res.summaryMessage),
                      if (res.deletedPaths.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...res.deletedPaths.take(6).map(
                              (path) => Text(
                                '− $path',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        if (res.deletedPaths.length > 6)
                          Text(
                            '… and ${res.deletedPaths.length - 6} more items',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                      if (res.removedPackages.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Removed packages & libraries: ${res.removedPackages.join(", ")}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (res.commandLogs.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...res.commandLogs.map(
                          (log) => Text(
                            '• $log',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
