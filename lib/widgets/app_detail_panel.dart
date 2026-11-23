import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/platform_parsers.dart';
import 'shared_badges.dart';

/// Filter mode for the selected app's data, registry, and leftover items.
enum DataFilterTab {
  all,
  userDataOnly,
  cacheOnly,
  registryOnly;

  String get label {
    switch (this) {
      case DataFilterTab.all:
        return 'All Items';
      case DataFilterTab.userDataOnly:
        return 'App Data & Config';
      case DataFilterTab.cacheOnly:
        return 'Cache & Logs';
      case DataFilterTab.registryOnly:
        return 'Registry';
    }
  }
}

/// Right-hand detail pane displaying Android-style Storage & Cache breakdown,
/// "Clear Cache Only", "Clear Selected Data (Reset App)", "Uninstall App + Leftovers",
/// associated data/registry items checklist, and Linux additional dependency libraries.
class AppDetailPanel extends StatefulWidget {
  final InstalledApp app;
  final bool isScanningData;
  final VoidCallback onRescanAppData;
  final VoidCallback onClearCacheOnly;
  final VoidCallback onClearAllData;
  final VoidCallback onUninstallApp;
  final VoidCallback onTerminateProcess;
  final void Function(String path) onRevealPath;
  final VoidCallback onSelectionChanged;

  const AppDetailPanel({
    super.key,
    required this.app,
    required this.isScanningData,
    required this.onRescanAppData,
    required this.onClearCacheOnly,
    required this.onClearAllData,
    required this.onUninstallApp,
    required this.onTerminateProcess,
    required this.onRevealPath,
    required this.onSelectionChanged,
  });

  @override
  State<AppDetailPanel> createState() => _AppDetailPanelState();
}

class _AppDetailPanelState extends State<AppDetailPanel> {
  DataFilterTab _dataFilter = DataFilterTab.all;

  @override
  void didUpdateWidget(covariant AppDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.app.id != oldWidget.app.id) {
      final hasRegistry = widget.app.platform == DesktopPlatformType.windows ||
          widget.app.registryItemsCount > 0;
      if (_dataFilter == DataFilterTab.registryOnly && !hasRegistry) {
        _dataFilter = DataFilterTab.all;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredDataItems = app.dataItems.where((item) {
      switch (_dataFilter) {
        case DataFilterTab.all:
          return true;
        case DataFilterTab.userDataOnly:
          return !item.isCacheLike && !item.isRegistryKey;
        case DataFilterTab.cacheOnly:
          return item.isCacheLike;
        case DataFilterTab.registryOnly:
          return item.isRegistryKey;
      }
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. App Header Card
          _buildHeaderCard(context, app),
          const SizedBox(height: 18),

          // 2. Android-Style Storage Breakdown & Reset Actions Card
          _buildAndroidStorageCard(context, app),
          const SizedBox(height: 18),

          // 3. Associated Data, Config, Cache, Registry & Leftover Files Table
          _buildDataItemsCard(context, app, filteredDataItems),

          // 4. Linux Additional Installed Libraries & Dependencies Card
          if (app.platform == DesktopPlatformType.linux ||
              app.linuxDependencies.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildLinuxDependenciesCard(
              context,
              app,
              colorScheme,
              theme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, InstalledApp app) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSystem = app.isSystemApp;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Avatar
          AppAvatar(
            name: app.name,
            isSystem: isSystem,
            size: 64,
            borderRadius: 16,
            fontSize: 28,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      app.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (app.version.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v${app.version}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _buildOriginBadge(context, app.origin),
                    _buildBadge(
                      label: app.installSource.label,
                      bgColor: colorScheme.secondaryContainer,
                      fgColor: colorScheme.onSecondaryContainer,
                      icon: Icons.inventory_2_outlined,
                    ),
                    if (app.isRunning)
                      _buildBadge(
                        label: 'Running',
                        bgColor: Colors.green.withValues(alpha: 0.16),
                        fgColor: Colors.green.shade800,
                        icon: Icons.bolt_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'ID: ${app.identifier}'
                  '${app.publisher.isNotEmpty ? "  ·  Publisher: ${app.publisher}" : ""}'
                  '${app.linuxPackageName != null ? "  ·  Package: ${app.linuxPackageName}" : ""}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        app.installPath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => widget.onRevealPath(app.installPath),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Reveal Location'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton.outlined(
                tooltip: 'Rescan application data & leftovers',
                onPressed:
                    widget.isScanningData ? null : widget.onRescanAppData,
                icon: widget.isScanningData
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (app.isRunning) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.onTerminateProcess,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Stop Process'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidStorageCard(BuildContext context, InstalledApp app) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final appBytes = app.appSizeBytes;
    final userDataBytes = app.userDataSizeBytes;
    final cacheBytes = app.cacheSizeBytes;
    final totalBytes = app.totalFootprintBytes;

    final appFlex = totalBytes > 0
        ? ((appBytes / totalBytes) * 1000).round().clamp(40, 1000)
        : 333;
    final dataFlex = totalBytes > 0 && userDataBytes > 0
        ? ((userDataBytes / totalBytes) * 1000).round().clamp(40, 1000)
        : 0;
    final cacheFlex = totalBytes > 0 && cacheBytes > 0
        ? ((cacheBytes / totalBytes) * 1000).round().clamp(40, 1000)
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                color: colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Storage Breakdown & Android-Style Data Reset (Keep App Installed)',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Total Footprint: ${FormatUtils.formatBytes(totalBytes)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visual proportional storage bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(
                    flex: appFlex,
                    child: Container(color: colorScheme.primary),
                  ),
                  if (dataFlex > 0)
                    Expanded(
                      flex: dataFlex,
                      child: Container(color: Colors.teal.shade500),
                    ),
                  if (cacheFlex > 0)
                    Expanded(
                      flex: cacheFlex,
                      child: Container(color: Colors.amber.shade600),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Storage metric boxes
          Row(
            children: [
              Expanded(
                child: _buildStorageMetricBox(
                  context: context,
                  dotColor: colorScheme.primary,
                  title: 'App Binary (App)',
                  value: FormatUtils.formatBytes(appBytes),
                  subtitle: 'Executable & bundled assets',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStorageMetricBox(
                  context: context,
                  dotColor: Colors.teal.shade500,
                  title: 'User Data & Registry',
                  value: FormatUtils.formatBytes(userDataBytes),
                  subtitle: app.registryItemsCount > 0
                      ? 'Profiles, settings & ${app.registryItemsCount} Registry keys'
                      : 'Accounts, preferences & containers',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStorageMetricBox(
                  context: context,
                  dotColor: Colors.amber.shade600,
                  title: 'Cache & Logs (Cache)',
                  value: FormatUtils.formatBytes(cacheBytes),
                  subtitle: 'Temporary cache, state & logs',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStorageMetricBox(
                  context: context,
                  dotColor: colorScheme.error,
                  title: 'Selected for Cleanup',
                  value: FormatUtils.formatBytes(app.selectedDataSizeBytes),
                  subtitle:
                      '${app.dataItems.where((i) => i.selected).length}/${app.dataItems.length} items checked',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Android-style action buttons + Full Uninstall button
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Clear Cache Only (Android "Clear Cache")
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed: widget.isScanningData || cacheBytes == 0
                    ? null
                    : widget.onClearCacheOnly,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  'Clear Cache Only (${FormatUtils.formatBytes(cacheBytes)})',
                ),
              ),

              // 2. Clear All Data / Reset App (Android "Clear Storage / Clear Data")
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed:
                    widget.isScanningData || app.selectedDataSizeBytes == 0
                        ? null
                        : widget.onClearAllData,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(
                  'Clear Selected Data / Reset App (${FormatUtils.formatBytes(app.selectedDataSizeBytes)})',
                ),
              ),

              // 3. Uninstall App + Leftovers (+ Linux Deps)
              Tooltip(
                message: app.isSystemApp
                    ? 'System applications are protected by the OS and cannot be uninstalled (you can still clear their cache or reset their data above).'
                    : 'Uninstall the application binary along with selected leftovers, registry keys, and Linux dependencies.',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  onPressed: widget.isScanningData || app.isSystemApp
                      ? null
                      : widget.onUninstallApp,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: Text(
                    app.isSystemApp
                        ? 'System App (Protected)'
                        : 'Uninstall App & Clean Leftovers (${FormatUtils.formatBytes(app.appSizeBytes + app.selectedDataSizeBytes + app.selectedLinuxDepsSizeBytes)})',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorageMetricBox({
    required BuildContext context,
    required Color dotColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataItemsCard(
    BuildContext context,
    InstalledApp app,
    List<AppDataItem> filteredItems,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasRegistryItems =
        app.platform == DesktopPlatformType.windows || app.registryItemsCount > 0;

    final availableTabs = DataFilterTab.values
        .where((t) => t != DataFilterTab.registryOnly || hasRegistryItems)
        .toList();

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_copy_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Associated Data, Config, Registry & Leftovers (${app.dataItems.length} items)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Select specific folders, files, or Windows Registry keys to clean during Data Reset or App Uninstall',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<DataFilterTab>(
              segments: availableTabs
                  .map(
                    (tab) => ButtonSegment<DataFilterTab>(
                      value: tab,
                      label: Text(
                        tab.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              selected: {
                availableTabs.contains(_dataFilter)
                    ? _dataFilter
                    : DataFilterTab.all,
              },
              onSelectionChanged: (set) {
                setState(() => _dataFilter = set.first);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: app.dataItems.isEmpty
                      ? null
                      : () {
                          for (final item in app.dataItems) {
                            item.selected = true;
                          }
                          widget.onSelectionChanged();
                        },
                  icon: const Icon(Icons.select_all_rounded, size: 17),
                  label: const Text('Select All'),
                ),
                TextButton.icon(
                  onPressed: app.dataItems.isEmpty
                      ? null
                      : () {
                          for (final item in app.dataItems) {
                            item.selected = item.isCacheLike;
                          }
                          widget.onSelectionChanged();
                        },
                  icon: const Icon(Icons.filter_alt_outlined, size: 17),
                  label: const Text('Select Cache & Logs Only (Keep Accounts)'),
                ),
                if (hasRegistryItems)
                  TextButton.icon(
                    onPressed: app.dataItems.isEmpty
                        ? null
                        : () {
                            for (final item in app.dataItems) {
                              if (item.isRegistryKey) {
                                item.selected = true;
                              }
                            }
                            widget.onSelectionChanged();
                          },
                    icon: const Icon(Icons.account_tree_outlined, size: 17),
                    label: const Text('Select Registry Keys'),
                  ),
                TextButton.icon(
                  onPressed: app.dataItems.isEmpty
                      ? null
                      : () {
                          for (final item in app.dataItems) {
                            item.selected = false;
                          }
                          widget.onSelectionChanged();
                        },
                  icon: const Icon(Icons.deselect_rounded, size: 17),
                  label: const Text('Deselect All'),
                ),
              ],
            ),
            const Divider(height: 16),

            if (widget.isScanningData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Scanning associated configurations, caches, containers, and Registry keys...',
                      ),
                    ],
                  ),
                ),
              )
            else if (filteredItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 44,
                        color: Colors.teal.shade500,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        app.dataItems.isEmpty
                            ? 'No associated user data, cache, or Registry keys detected for this application'
                            : 'No items match the selected category tab',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredItems.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    leading: Checkbox(
                      value: item.selected,
                      onChanged: (val) {
                        item.selected = val ?? false;
                        widget.onSelectionChanged();
                      },
                    ),
                    title: Row(
                      children: [
                        DataCategoryBadge(item: item),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          FormatUtils.formatBytes(item.sizeBytes),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          item.path,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                          ),
                        ),
                        Text(
                          '${item.description}  ·  Modified: ${FormatUtils.formatDate(item.lastModified)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        item.isRegistryKey
                            ? Icons.account_tree_outlined
                            : Icons.folder_open_rounded,
                        size: 18,
                      ),
                      tooltip: item.isRegistryKey
                          ? 'Open in Registry Editor (regedit)'
                          : 'Reveal in File Manager',
                      onPressed: () => widget.onRevealPath(item.path),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinuxDependenciesCard(
    BuildContext context,
    InstalledApp app,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final selectedDeps =
        app.linuxDependencies.where((d) => d.selected).toList();
    final cmdPreview = PlatformParsers.buildLinuxUninstallCommand(
      app: app,
      selectedDependencies: selectedDeps,
    ).join(' ');

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.extension_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Linux Additional Installed Libraries (${app.linuxDependencies.length} packages)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Analyzes /var/log/apt/history.log transactions, apt-get -s autoremove, and reverse dependency trees to separate exclusive auto-installed libraries from shared libraries.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${selectedDeps.length} selected · ${FormatUtils.formatBytes(app.selectedLinuxDepsSizeBytes)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: app.linuxDependencies.isEmpty
                      ? null
                      : () {
                          for (final dep in app.linuxDependencies) {
                            dep.selected = dep.isSafeToRemove;
                          }
                          widget.onSelectionChanged();
                        },
                  icon: const Icon(Icons.verified_user_outlined, size: 17),
                  label: const Text(
                    'Select Safe Exclusive Libraries (Recommended)',
                  ),
                ),
                TextButton.icon(
                  onPressed: app.linuxDependencies.isEmpty
                      ? null
                      : () {
                          for (final dep in app.linuxDependencies) {
                            dep.selected = false;
                          }
                          widget.onSelectionChanged();
                        },
                  icon: const Icon(Icons.deselect_rounded, size: 17),
                  label: const Text('Deselect All'),
                ),
              ],
            ),
            const Divider(height: 12),
            if (app.linuxDependencies.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No orphaned auto-installed dependency libraries detected for this package.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: app.linuxDependencies.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final dep = app.linuxDependencies[index];
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: dep.selected,
                    onChanged: (val) {
                      dep.selected = val ?? false;
                      widget.onSelectionChanged();
                    },
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            dep.packageName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: LinuxDepSafetyBadge(dependency: dep),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          FormatUtils.formatBytes(dep.sizeBytes),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'v${dep.version} · ${dep.description}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              CommandPreviewBox(
                command: cmdPreview,
                copiedSnackMessage:
                    'Copied Linux dependency removal command to clipboard',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOriginBadge(BuildContext context, AppOriginType origin) {
    final isSystem = origin == AppOriginType.systemApp;
    return _buildBadge(
      label: origin.label,
      bgColor: isSystem
          ? Colors.amber.withValues(alpha: 0.2)
          : Colors.indigo.withValues(alpha: 0.15),
      fgColor: isSystem ? Colors.amber.shade900 : Colors.indigo.shade800,
      icon: isSystem ? Icons.shield_outlined : Icons.person_outline_rounded,
    );
  }

  Widget _buildBadge({
    required String label,
    required Color bgColor,
    required Color fgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
