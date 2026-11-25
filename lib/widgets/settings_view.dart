import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/app_models.dart';
import 'shared_badges.dart';

/// Settings, Whitelist Management, Manual App Associations, and About view.
class SettingsView extends StatefulWidget {
  final AppCleanerSettings settings;
  final List<String> builtInWhitelist;
  final String configDirectoryPath;
  final ValueChanged<AppCleanerSettings> onUpdateSettings;
  final void Function(String path) onRevealPath;

  const SettingsView({
    super.key,
    required this.settings,
    required this.builtInWhitelist,
    required this.configDirectoryPath,
    required this.onUpdateSettings,
    required this.onRevealPath,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _whitelistInputController =
      TextEditingController();
  final TextEditingController _builtInFilterController =
      TextEditingController();
  String _builtInFilter = '';

  @override
  void dispose() {
    _whitelistInputController.dispose();
    _builtInFilterController.dispose();
    super.dispose();
  }

  void _addCustomWhitelistRule() {
    final value = _whitelistInputController.text.trim();
    if (value.isEmpty) return;
    final exists = widget.settings.customWhitelist.any(
      (r) => r.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      _whitelistInputController.clear();
      showCapsuleToast(
        context,
        '"$value" is already in the whitelist.',
        tone: CapsuleToastTone.info,
      );
      return;
    }
    final updated = [value, ...widget.settings.customWhitelist];
    _whitelistInputController.clear();
    widget.onUpdateSettings(
      widget.settings.copyWith(customWhitelist: updated),
    );
    showCapsuleToast(
      context,
      'Added "$value" to custom whitelist.',
      tone: CapsuleToastTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = widget.settings;

    final filteredBuiltIn = _builtInFilter.trim().isEmpty
        ? widget.builtInWhitelist
        : widget.builtInWhitelist
            .where(
              (w) => w.toLowerCase().contains(_builtInFilter.toLowerCase()),
            )
            .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final hPad = isCompact ? 16.0 : 24.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Banner
            Container(
              padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 14),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.settings_rounded,
                      color: colorScheme.onSecondaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings & Preferences',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Configure subfolder scanning, safety defaults, whitelist rules, manual app links, and view application info.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Settings Sections
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Scanning & Cleanup Preferences
                    _buildSectionContainer(
                      context: context,
                      icon: Icons.tune_rounded,
                      title: 'Scanning & Cleanup Preferences',
                      subtitle:
                          'Control how AppCleaner discovers nested vendor folders and handles file removal',
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Inspect 1-Level Vendor Subfolders',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Scans one directory deeper inside company/publisher folders (e.g. Softdeluxe/Free Download Manager or Google/Chrome) to link app data and avoid false leftover alerts. Uses a 20-second directory cache to keep scans fast.',
                            ),
                            value: settings.scanVendorSubfolders,
                            onChanged: (v) => widget.onUpdateSettings(
                              settings.copyWith(scanVendorSubfolders: v),
                            ),
                          ),
                          const Divider(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Default to System Trash (Recoverable)',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Pre-selects "Move to System Trash / Recycle Bin" instead of permanent deletion in cleanup and uninstall confirmation dialogs.',
                            ),
                            value: settings.defaultMoveToTrash,
                            onChanged: (v) => widget.onUpdateSettings(
                              settings.copyWith(defaultMoveToTrash: v),
                            ),
                          ),
                          const Divider(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Expand Orphaned Leftover Cards by Default',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'When disabled (default), leftover group cards start collapsed for a clean overview.',
                            ),
                            value: settings.expandOrphanCardsByDefault,
                            onChanged: (v) => widget.onUpdateSettings(
                              settings.copyWith(expandOrphanCardsByDefault: v),
                            ),
                          ),
                          const Divider(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Auto-Scan Orphaned Leftovers on Tab Open',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Automatically run a leftover scan the first time you switch to the Orphaned Leftovers view.',
                            ),
                            value: settings.autoScanOrphansOnOpen,
                            onChanged: (v) => widget.onUpdateSettings(
                              settings.copyWith(autoScanOrphansOnOpen: v),
                            ),
                          ),
                          const Divider(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Include System Apps in Initial Filter',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Open Installed Apps on "All" instead of "User Apps" when launching AppCleaner.',
                            ),
                            value: settings.includeSystemAppsByDefault,
                            onChanged: (v) => widget.onUpdateSettings(
                              settings.copyWith(includeSystemAppsByDefault: v),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 2. Whitelist Rules (Custom + Built-in)
                    _buildSectionContainer(
                      context: context,
                      icon: Icons.verified_user_outlined,
                      title:
                          'Whitelist Rules (${settings.customWhitelist.length} custom · ${widget.builtInWhitelist.length} built-in)',
                      subtitle:
                          'Whitelisted paths, folder names, and Bundle IDs are excluded from leftover cleanup and app data resets',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _whitelistInputController,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Add folder name, Bundle ID, or full path to whitelist...',
                                    prefixIcon: const Icon(
                                      Icons.shield_outlined,
                                      size: 19,
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerLow,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) => _addCustomWhitelistRule(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonalIcon(
                                onPressed: _addCustomWhitelistRule,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (settings.customWhitelist.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'No custom whitelist entries yet. You can add rules above or right-click any card in Orphaned Leftovers and select "Add to Whitelist".',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: settings.customWhitelist.map((rule) {
                                return InputChip(
                                  label: Text(
                                    rule,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  onDeleted: () {
                                    final next = settings.customWhitelist
                                        .where((r) => r != rule)
                                        .toList();
                                    widget.onUpdateSettings(
                                      settings.copyWith(customWhitelist: next),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 12),
                          Theme(
                            data: theme.copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'Built-in Protected System Folders & Identifiers (${widget.builtInWhitelist.length})',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Automatically ignored on ${kIsWeb ? "Web Simulator" : DesktopPlatformType.current.label} to protect OS & runtime components',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              children: [
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _builtInFilterController,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Filter built-in protected names...',
                                    prefixIcon:
                                        const Icon(Icons.search, size: 18),
                                    suffixIcon: _builtInFilter.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear Filter',
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                            ),
                                            onPressed: () {
                                              _builtInFilterController.clear();
                                              setState(
                                                () => _builtInFilter = '',
                                              );
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
                                  onChanged: (v) =>
                                      setState(() => _builtInFilter = v),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: filteredBuiltIn.map((name) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 3. Manual App Associations
                    _buildSectionContainer(
                      context: context,
                      icon: Icons.link_rounded,
                      title:
                          'Manual App Associations (${settings.customAssociations.length})',
                      subtitle:
                          'Custom links created via right-click in Orphaned Leftovers ("Associate with App...")',
                      child: settings.customAssociations.isEmpty
                          ? Text(
                              'No manual app associations configured. Right-click any leftover folder in Orphaned Leftovers to link it to an installed application.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: settings.customAssociations.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final assoc = settings.customAssociations[idx];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder_special_outlined,
                                    size: 20,
                                  ),
                                  title: Text(
                                    '${assoc.label}  →  ${assoc.appName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    assoc.path,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Remove Association',
                                    icon: const Icon(
                                      Icons.link_off_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      final next = settings.customAssociations
                                          .where((a) => a.path != assoc.path)
                                          .toList();
                                      widget.onUpdateSettings(
                                        settings.copyWith(
                                          customAssociations: next,
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 18),

                    // 4. About AppCleaner
                    _buildSectionContainer(
                      context: context,
                      icon: Icons.info_outline_rounded,
                      title: 'About AppCleaner',
                      subtitle: 'Application version, architecture, and local configuration storage',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  'assets/app_icon.png',
                                  width: 56,
                                  height: 56,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'AppCleaner',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'v1.1.0',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Application ID: com.yin.appcleaner  ·  Platform: ${kIsWeb ? "Web UI Debugger" : DesktopPlatformType.current.label}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontFamily: 'monospace',
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Cross-platform desktop application uninstaller, Android-style app cache & data resetter, Windows Registry cleaner, Linux orphan dependency analyzer, and leftover scanner for macOS (arm64), Linux (amd64), and Windows (x64).',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SelectableText(
                                    'Config & History Dir: ${widget.configDirectoryPath}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (!kIsWeb)
                                  TextButton.icon(
                                    onPressed: () => widget.onRevealPath(
                                      widget.configDirectoryPath,
                                    ),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 15,
                                    ),
                                    label: const Text('Open Folder'),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                widget.onUpdateSettings(
                                  const AppCleanerSettings(),
                                );
                                showCapsuleToast(
                                  context,
                                  'Restored default preferences.',
                                  tone: CapsuleToastTone.info,
                                );
                              },
                              icon: const Icon(
                                Icons.restore_rounded,
                                size: 17,
                              ),
                              label: const Text('Reset All Settings to Default'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionContainer({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
