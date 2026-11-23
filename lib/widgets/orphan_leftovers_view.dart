import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../utils/format_utils.dart';

/// Dedicated view for scanning, inspecting, and deleting orphaned leftover files
/// and orphaned Windows Registry keys left behind by previously uninstalled applications.
class OrphanLeftoversView extends StatefulWidget {
  final List<OrphanLeftoverGroup> orphanGroups;
  final bool isScanning;
  final VoidCallback onRescan;
  final VoidCallback onCleanSelected;
  final void Function(String path) onRevealPath;
  final VoidCallback onSelectionChanged;

  const OrphanLeftoversView({
    super.key,
    required this.orphanGroups,
    required this.isScanning,
    required this.onRescan,
    required this.onCleanSelected,
    required this.onRevealPath,
    required this.onSelectionChanged,
  });

  @override
  State<OrphanLeftoversView> createState() => _OrphanLeftoversViewState();
}

class _OrphanLeftoversViewState extends State<OrphanLeftoversView> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredGroups = widget.orphanGroups.where((g) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return g.suspectedAppName.toLowerCase().contains(q) ||
          g.identifier.toLowerCase().contains(q) ||
          g.items.any((i) => i.path.toLowerCase().contains(q));
    }).toList();

    final totalOrphanBytes = widget.orphanGroups.fold<int>(
      0,
      (sum, g) => sum + g.totalSizeBytes,
    );
    final selectedOrphanBytes = widget.orphanGroups.fold<int>(
      0,
      (sum, g) => sum + g.selectedSizeBytes,
    );
    final selectedItemCount = widget.orphanGroups.fold<int>(
      0,
      (sum, g) => sum + g.selectedCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Summary Banner
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_delete_rounded,
                      size: 28,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orphaned Leftovers Scanner',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cross-references user directories and Windows Registry hives (HKCU/HKLM) against currently installed apps to detect residual configs, caches, containers, and registry keys left by previously uninstalled apps.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: widget.isScanning ? null : widget.onRescan,
                    icon: widget.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      widget.isScanning ? 'Scanning...' : 'Rescan Leftovers',
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onPressed: widget.isScanning || selectedItemCount == 0
                        ? null
                        : widget.onCleanSelected,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(
                      'Clean Selected ($selectedItemCount items · ${FormatUtils.formatBytes(selectedOrphanBytes)})',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 340,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText:
                            'Filter by app name, Bundle ID, path, or Registry key...',
                        prefixIcon: const Icon(Icons.search, size: 20),
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
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: widget.orphanGroups.isEmpty
                        ? null
                        : () {
                            for (final g in widget.orphanGroups) {
                              for (final i in g.items) {
                                i.selected = true;
                              }
                            }
                            widget.onSelectionChanged();
                          },
                    icon: const Icon(Icons.select_all_rounded, size: 18),
                    label: const Text('Select All'),
                  ),
                  TextButton.icon(
                    onPressed: widget.orphanGroups.isEmpty
                        ? null
                        : () {
                            for (final g in widget.orphanGroups) {
                              for (final i in g.items) {
                                i.selected = false;
                              }
                            }
                            widget.onSelectionChanged();
                          },
                    icon: const Icon(Icons.deselect_rounded, size: 18),
                    label: const Text('Deselect All'),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Found ${widget.orphanGroups.length} orphaned app groups · Total ${FormatUtils.formatBytes(totalOrphanBytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Main List Content
        Expanded(
          child: widget.isScanning
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Scanning user directories and Registry hives for orphaned leftovers...',
                      ),
                    ],
                  ),
                )
              : filteredGroups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 64,
                            color: Colors.teal.shade500,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.orphanGroups.isEmpty
                                ? 'No orphaned leftovers found on this system!'
                                : 'No leftover groups match your search filter',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click "Rescan Leftovers" in the top-right corner anytime to check again.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: filteredGroups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final group = filteredGroups[index];
                        return _buildOrphanGroupCard(context, group);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildOrphanGroupCard(
    BuildContext context,
    OrphanLeftoverGroup group,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: Checkbox(
          tristate: true,
          value:
              group.allSelected ? true : (group.anySelected ? null : false),
          onChanged: (val) {
            final target = val ?? false;
            for (final item in group.items) {
              item.selected = target;
            }
            widget.onSelectionChanged();
          },
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                group.suspectedAppName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Orphaned · ${group.items.length} items',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            const Spacer(),
            Text(
              FormatUtils.formatBytes(group.totalSizeBytes),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
        subtitle: Text(
          'ID: ${group.identifier} · ${group.confidenceReason}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          const Divider(height: 1),
          ...group.items.map((item) {
            return ListTile(
              dense: true,
              leading: Checkbox(
                value: item.selected,
                onChanged: (val) {
                  item.selected = val ?? false;
                  widget.onSelectionChanged();
                },
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.isRegistryKey
                          ? Colors.deepPurple.withValues(alpha: 0.16)
                          : colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      item.category.shortLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.isRegistryKey
                            ? Colors.deepPurple.shade800
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    FormatUtils.formatBytes(item.sizeBytes),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${item.path}  ·  Modified: ${FormatUtils.formatDate(item.lastModified)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                ),
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
          }),
        ],
      ),
    );
  }
}
