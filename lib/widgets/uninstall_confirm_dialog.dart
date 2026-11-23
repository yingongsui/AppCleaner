import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/platform_parsers.dart';
import 'shared_badges.dart';

/// Confirmation dialog for uninstalling an application, cleaning its associated
/// data/leftovers (including Windows Registry keys), and (on Linux) selectively
/// uninstalling additional libraries that were pulled in when the app was installed.
class UninstallConfirmDialog extends StatefulWidget {
  final InstalledApp app;

  const UninstallConfirmDialog({
    super.key,
    required this.app,
  });

  @override
  State<UninstallConfirmDialog> createState() => _UninstallConfirmDialogState();
}

class UninstallDialogChoices {
  final bool removeSelectedData;
  final bool removeSelectedLinuxDeps;
  final bool moveToTrashOnMac;

  const UninstallDialogChoices({
    required this.removeSelectedData,
    required this.removeSelectedLinuxDeps,
    required this.moveToTrashOnMac,
  });
}

class _UninstallConfirmDialogState extends State<UninstallConfirmDialog> {
  bool _removeSelectedData = true;
  bool _removeSelectedLinuxDeps = true;
  bool _moveToTrashOnMac = true;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasLinuxDeps = app.linuxDependencies.isNotEmpty;
    final selectedDataItems = app.dataItems.where((d) => d.selected).toList();
    final selectedDeps =
        app.linuxDependencies.where((d) => d.selected).toList();

    final totalFreed = app.appSizeBytes +
        (_removeSelectedData ? app.selectedDataSizeBytes : 0) +
        (_removeSelectedLinuxDeps ? app.selectedLinuxDepsSizeBytes : 0);

    final linuxCmd = hasLinuxDeps || app.platform == DesktopPlatformType.linux
        ? PlatformParsers.buildLinuxUninstallCommand(
            app: app,
            selectedDependencies:
                _removeSelectedLinuxDeps ? selectedDeps : const [],
          ).join(' ')
        : null;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.delete_forever_rounded,
              color: colorScheme.onErrorContainer,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uninstall "${app.name}" & Clean Leftovers',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${app.identifier} · Estimated space to free: ${FormatUtils.formatBytes(totalFreed)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(),
              // 1. Application Binary Section
              _buildSectionCard(
                context: context,
                icon: Icons.apps_rounded,
                title: 'Application Binary (${app.installSource.label})',
                subtitle: app.installPath,
                trailingText: FormatUtils.formatBytes(app.appSizeBytes),
                child: app.platform == DesktopPlatformType.macos
                    ? SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Move to Trash (allows restoring from Trash; disable to delete permanently)',
                        ),
                        value: _moveToTrashOnMac,
                        onChanged: (v) => setState(() => _moveToTrashOnMac = v),
                      )
                    : null,
              ),
              const SizedBox(height: 12),

              // 2. Associated Leftover Data & Registry Items
              _buildSectionCard(
                context: context,
                icon: Icons.cleaning_services_rounded,
                title:
                    'Remove Associated Data, Config & Registry Leftovers (${selectedDataItems.length}/${app.dataItems.length})',
                subtitle:
                    'Includes user configuration, cache, sandbox containers, logs, and Windows Registry keys',
                trailingText: FormatUtils.formatBytes(
                  _removeSelectedData ? app.selectedDataSizeBytes : 0,
                ),
                leadingCheckbox: Checkbox(
                  value: _removeSelectedData,
                  onChanged: (v) =>
                      setState(() => _removeSelectedData = v ?? true),
                ),
                child: _removeSelectedData && app.dataItems.isNotEmpty
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: app.dataItems.length,
                          itemBuilder: (context, index) {
                            final item = app.dataItems[index];
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: item.selected,
                              onChanged: (val) {
                                setState(() {
                                  item.selected = val ?? false;
                                });
                              },
                              title: Row(
                                children: [
                                  DataCategoryBadge(item: item),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    FormatUtils.formatBytes(item.sizeBytes),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    : null,
              ),

              // 3. Linux Additional Installed Libraries Section
              if (hasLinuxDeps) ...[
                const SizedBox(height: 12),
                _buildSectionCard(
                  context: context,
                  icon: Icons.extension_rounded,
                  title:
                      'Linux Additional Installed Libraries (${selectedDeps.length}/${app.linuxDependencies.length} selected)',
                  subtitle:
                      'Auto-installed dependency libraries pulled in with this package and not required by other apps',
                  trailingText: FormatUtils.formatBytes(
                    _removeSelectedLinuxDeps
                        ? app.selectedLinuxDepsSizeBytes
                        : 0,
                  ),
                  leadingCheckbox: Checkbox(
                    value: _removeSelectedLinuxDeps,
                    onChanged: (v) =>
                        setState(() => _removeSelectedLinuxDeps = v ?? true),
                  ),
                  child: _removeSelectedLinuxDeps
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 190),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: app.linuxDependencies.length,
                                itemBuilder: (context, index) {
                                  final dep = app.linuxDependencies[index];
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: dep.selected,
                                    onChanged: (val) {
                                      setState(() {
                                        dep.selected = val ?? false;
                                      });
                                    },
                                    title: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            dep.packageName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: LinuxDepSafetyBadge(
                                            dependency: dep,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          FormatUtils.formatBytes(
                                            dep.sizeBytes,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${dep.version} · ${dep.description}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (linuxCmd != null) ...[
                              const SizedBox(height: 8),
                              CommandPreviewBox(command: linuxCmd),
                            ],
                          ],
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () {
            Navigator.of(context).pop(
              UninstallDialogChoices(
                removeSelectedData: _removeSelectedData,
                removeSelectedLinuxDeps: _removeSelectedLinuxDeps,
                moveToTrashOnMac: _moveToTrashOnMac,
              ),
            );
          },
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text(
            'Uninstall & Free ${FormatUtils.formatBytes(totalFreed)}',
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailingText,
    Widget? leadingCheckbox,
    Widget? child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leadingCheckbox != null) ...[
                  leadingCheckbox,
                  const SizedBox(width: 4),
                ],
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trailingText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (child != null) ...[
              const Divider(height: 16),
              child,
            ],
          ],
        ),
      ),
    );
  }
}
