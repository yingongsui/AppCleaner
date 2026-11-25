import 'package:material_ui/material_ui.dart';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import 'shared_badges.dart';

enum _OrphanMenuAction {
  associateWithApp,
  addToWhitelist,
  revealLocation,
}

/// Dedicated view for scanning, inspecting, and deleting orphaned leftover files
/// and orphaned Windows Registry keys left behind by previously uninstalled applications.
class OrphanLeftoversView extends StatefulWidget {
  final List<OrphanLeftoverGroup> orphanGroups;
  final List<InstalledApp> installedApps;
  final bool isScanning;
  final bool expandCardsByDefault;
  final VoidCallback onRescan;
  final VoidCallback onCleanSelected;
  final void Function(String path) onRevealPath;
  final VoidCallback onSelectionChanged;
  final void Function(
    OrphanLeftoverGroup group,
    InstalledApp targetApp, {
    AppDataItem? singleItem,
  }) onAssociateWithApp;
  final void Function(
    OrphanLeftoverGroup group, {
    AppDataItem? singleItem,
  }) onAddToWhitelist;

  const OrphanLeftoversView({
    super.key,
    required this.orphanGroups,
    required this.installedApps,
    required this.isScanning,
    this.expandCardsByDefault = false,
    required this.onRescan,
    required this.onCleanSelected,
    required this.onRevealPath,
    required this.onSelectionChanged,
    required this.onAssociateWithApp,
    required this.onAddToWhitelist,
  });

  @override
  State<OrphanLeftoversView> createState() => _OrphanLeftoversViewState();
}

class _OrphanLeftoversViewState extends State<OrphanLeftoversView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool? _overrideExpanded;
  int _expandGeneration = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

    final effectiveExpanded = _overrideExpanded ?? widget.expandCardsByDefault;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Summary Banner
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 860;
            final isNarrow = constraints.maxWidth < 560;
            final hPad = isNarrow ? 16.0 : 24.0;

            final headerIdentity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_delete_rounded,
                    size: isNarrow ? 24 : 28,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
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
                        'Cross-references user directories and Windows Registry hives against installed apps. Right-click any leftover card or item to associate it with an installed app or add it to the whitelist.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final rescanButton = OutlinedButton.icon(
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
            );

            final cleanButton = FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              onPressed: widget.isScanning || selectedItemCount == 0
                  ? null
                  : widget.onCleanSelected,
              icon: const Icon(Icons.cleaning_services_rounded),
              label: Text(
                'Clean Selected ($selectedItemCount items · ${FormatUtils.formatBytes(selectedOrphanBytes)})',
              ),
            );

            return Container(
              padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 14),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isCompact)
                    Row(
                      children: [
                        Expanded(child: headerIdentity),
                        const SizedBox(width: 16),
                        rescanButton,
                        const SizedBox(width: 12),
                        cleanButton,
                      ],
                    )
                  else ...[
                    headerIdentity,
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [rescanButton, cleanButton],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: isNarrow ? double.infinity : 260,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                'Filter by app name, Bundle ID, or path...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear Filter',
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
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
                      ),
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
                      TextButton.icon(
                        onPressed: widget.orphanGroups.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _overrideExpanded = !effectiveExpanded;
                                  _expandGeneration++;
                                });
                              },
                        icon: Icon(
                          effectiveExpanded
                              ? Icons.unfold_less_rounded
                              : Icons.unfold_more_rounded,
                          size: 18,
                        ),
                        label: Text(
                          effectiveExpanded ? 'Collapse All' : 'Expand All',
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Found ${widget.orphanGroups.length} groups · Total ${FormatUtils.formatBytes(totalOrphanBytes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
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
                            'Click "Rescan Leftovers" anytime to check again.',
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
                        return _buildOrphanGroupCard(
                          context,
                          group,
                          effectiveExpanded: effectiveExpanded,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    OrphanLeftoverGroup group, {
    AppDataItem? singleItem,
  }) async {
    final overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<_OrphanMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: _buildMenuItems(group, singleItem: singleItem),
    );
    if (!context.mounted || selected == null) return;
    await _handleMenuAction(context, selected, group, singleItem: singleItem);
  }

  List<PopupMenuEntry<_OrphanMenuAction>> _buildMenuItems(
    OrphanLeftoverGroup group, {
    AppDataItem? singleItem,
  }) {
    final targetLabel = singleItem?.name ?? group.suspectedAppName;
    return [
      PopupMenuItem<_OrphanMenuAction>(
        value: _OrphanMenuAction.associateWithApp,
        child: Row(
          children: [
            const Icon(Icons.link_rounded, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Associate "$targetLabel" with App...',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      const PopupMenuItem<_OrphanMenuAction>(
        value: _OrphanMenuAction.addToWhitelist,
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 18),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Add to Whitelist',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      if (singleItem != null || group.items.length == 1)
        const PopupMenuItem<_OrphanMenuAction>(
          value: _OrphanMenuAction.revealLocation,
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 18),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Reveal in File Manager',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    _OrphanMenuAction action,
    OrphanLeftoverGroup group, {
    AppDataItem? singleItem,
  }) async {
    switch (action) {
      case _OrphanMenuAction.associateWithApp:
        final chosenApp = await _pickInstalledAppDialog(
          context,
          targetLabel: singleItem?.name ?? group.suspectedAppName,
        );
        if (chosenApp != null && context.mounted) {
          widget.onAssociateWithApp(
            group,
            chosenApp,
            singleItem: singleItem,
          );
        }
      case _OrphanMenuAction.addToWhitelist:
        widget.onAddToWhitelist(group, singleItem: singleItem);
      case _OrphanMenuAction.revealLocation:
        final path = singleItem?.path ?? group.items.first.path;
        widget.onRevealPath(path);
    }
  }

  Future<InstalledApp?> _pickInstalledAppDialog(
    BuildContext context, {
    required String targetLabel,
  }) {
    String filter = '';
    return showDialog<InstalledApp>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final colorScheme = Theme.of(ctx).colorScheme;
          final q = filter.trim().toLowerCase();
          final matches = widget.installedApps.where((app) {
            if (q.isEmpty) return true;
            return app.name.toLowerCase().contains(q) ||
                app.identifier.toLowerCase().contains(q) ||
                app.publisher.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: Text('Associate "$targetLabel" with App'),
            content: SizedBox(
              width: 500,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select the installed application that owns this folder/item. It will be linked to that app\'s data list and hidden from Orphaned Leftovers.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search installed applications...',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      isDense: true,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setDialogState(() => filter = v),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  Expanded(
                    child: matches.isEmpty
                        ? Center(
                            child: Text(
                              'No matching installed applications',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final app = matches[idx];
                              return ListTile(
                                dense: true,
                                leading: AppAvatar(
                                  name: app.name,
                                  isSystem: app.isSystemApp,
                                  isSelfApp: app.isSelfApp,
                                  iconBytes: app.iconBytes,
                                  size: 34,
                                  borderRadius: 8,
                                  fontSize: 14,
                                ),
                                title: Text(
                                  app.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  app.identifier,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.add_link_rounded,
                                  size: 18,
                                ),
                                onTap: () => Navigator.of(ctx).pop(app),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrphanGroupCard(
    BuildContext context,
    OrphanLeftoverGroup group, {
    required bool effectiveExpanded,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition, group),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: ExpansionTile(
          key: ValueKey(
            '${group.id}_${effectiveExpanded}_$_expandGeneration',
          ),
          initiallyExpanded: effectiveExpanded,
          shape: const Border(),
          leading: Checkbox(
            tristate: true,
            value: group.allSelected
                ? true
                : (group.anySelected ? null : false),
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
              Expanded(
                child: Row(
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
                    Flexible(
                      flex: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              colorScheme.errorContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Orphaned · ${group.items.length} items',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                FormatUtils.formatBytes(group.totalSizeBytes),
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_OrphanMenuAction>(
                tooltip: 'More Actions (Associate / Whitelist)',
                icon: const Icon(Icons.more_vert_rounded, size: 19),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onSelected: (action) =>
                    _handleMenuAction(context, action, group),
                itemBuilder: (_) => _buildMenuItems(group),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompactItem = constraints.maxWidth < 540;
                return Column(
                  children: group.items.map((item) {
                    final revealBtn = IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
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
                    );

                    final itemMenuBtn = PopupMenuButton<_OrphanMenuAction>(
                      tooltip: 'Item Actions',
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onSelected: (action) => _handleMenuAction(
                        context,
                        action,
                        group,
                        singleItem: item,
                      ),
                      itemBuilder: (_) =>
                          _buildMenuItems(group, singleItem: item),
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapUp: (details) => _showContextMenu(
                        context,
                        details.globalPosition,
                        group,
                        singleItem: item,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              visualDensity: VisualDensity.compact,
                              value: item.selected,
                              onChanged: (val) {
                                item.selected = val ?? false;
                                widget.onSelectionChanged();
                              },
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isCompactItem) ...[
                                    Row(
                                      children: [
                                        DataCategoryBadge(item: item),
                                        const Spacer(),
                                        Text(
                                          FormatUtils.formatBytes(
                                            item.sizeBytes,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        revealBtn,
                                        itemMenuBtn,
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ] else
                                    Row(
                                      children: [
                                        DataCategoryBadge(item: item),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          FormatUtils.formatBytes(
                                            item.sizeBytes,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        revealBtn,
                                        itemMenuBtn,
                                      ],
                                    ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${item.path}  ·  Modified: ${FormatUtils.formatDate(item.lastModified)}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
