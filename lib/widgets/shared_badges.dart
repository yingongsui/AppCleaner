import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/app_models.dart';

/// Displays the real native application icon (when available), AppCleaner's own
/// bundled asset icon (when [isSelfApp] is true), or a clean gradient fallback.
class AppAvatar extends StatelessWidget {
  final String name;
  final bool isSystem;
  final bool isSelfApp;
  final Uint8List? iconBytes;
  final double size;
  final double borderRadius;
  final double fontSize;

  const AppAvatar({
    super.key,
    required this.name,
    required this.isSystem,
    this.isSelfApp = false,
    this.iconBytes,
    this.size = 40,
    this.borderRadius = 10,
    this.fontSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    if (isSelfApp) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          'assets/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => _buildFallbackAvatar(context),
        ),
      );
    }

    if (iconBytes != null && iconBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.memory(
          iconBytes!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _buildFallbackAvatar(context),
        ),
      );
    }

    return _buildFallbackAvatar(context);
  }

  Widget _buildFallbackAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSystem
              ? [Colors.blueGrey.shade500, Colors.blueGrey.shade800]
              : [colorScheme.primary, colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : 'A',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Shared badge pill for an [AppDataItem]'s category (Cache / Config / App Data / Registry).
class DataCategoryBadge extends StatelessWidget {
  final AppDataItem item;

  const DataCategoryBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    if (item.isRegistryKey) {
      bg = Colors.deepPurple.withValues(alpha: isDark ? 0.28 : 0.16);
      fg = isDark ? Colors.deepPurple.shade200 : Colors.deepPurple.shade800;
    } else if (item.isCacheLike) {
      bg = Colors.amber.withValues(alpha: isDark ? 0.24 : 0.2);
      fg = isDark ? Colors.amber.shade300 : Colors.amber.shade900;
    } else {
      bg = Colors.teal.withValues(alpha: isDark ? 0.24 : 0.15);
      fg = isDark ? Colors.teal.shade200 : Colors.teal.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        item.category.shortLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

/// Shared safety badge pill for a [LinuxDependencyPackage].
class LinuxDepSafetyBadge extends StatelessWidget {
  final LinuxDependencyPackage dependency;
  final double fontSize;

  const LinuxDepSafetyBadge({
    super.key,
    required this.dependency,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: dependency.isSafeToRemove
            ? Colors.teal.withValues(alpha: isDark ? 0.25 : 0.15)
            : Colors.amber.withValues(alpha: isDark ? 0.25 : 0.22),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        dependency.safetyBadgeText,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: dependency.isSafeToRemove
              ? (isDark ? Colors.teal.shade200 : Colors.teal.shade800)
              : (isDark ? Colors.amber.shade300 : Colors.amber.shade900),
        ),
      ),
    );
  }
}

/// Shared terminal command preview container with one-click copy action.
class CommandPreviewBox extends StatelessWidget {
  final String command;
  final String copiedSnackMessage;

  const CommandPreviewBox({
    super.key,
    required this.command,
    this.copiedSnackMessage = 'Copied Linux uninstall command to clipboard',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              command,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 17),
            tooltip: 'Copy Command',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              showCapsuleToast(
                context,
                copiedSnackMessage,
                tone: CapsuleToastTone.success,
                icon: Icons.check_rounded,
                duration: const Duration(seconds: 2),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Reusable toggle card for cleanup confirmation dialogs letting the user
/// choose between moving files to the OS Trash / Recycle Bin (recoverable,
/// default) or permanently deleting them from disk.
class DeletionModeToggle extends StatelessWidget {
  final bool moveToTrash;
  final ValueChanged<bool> onChanged;

  const DeletionModeToggle({
    super.key,
    required this.moveToTrash,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = moveToTrash
        ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.30 : 0.35)
        : colorScheme.errorContainer.withValues(alpha: isDark ? 0.35 : 0.45);
    final borderColor = moveToTrash
        ? colorScheme.primary.withValues(alpha: 0.35)
        : colorScheme.error.withValues(alpha: 0.45);
    final iconColor = moveToTrash ? colorScheme.primary : colorScheme.error;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        dense: true,
        secondary: Icon(
          moveToTrash
              ? Icons.restore_from_trash_rounded
              : Icons.delete_forever_rounded,
          color: iconColor,
        ),
        title: Text(
          moveToTrash
              ? 'Move to System Trash (Recoverable)'
              : 'Permanently Delete (Irreversible)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: moveToTrash ? colorScheme.onSurface : colorScheme.error,
          ),
        ),
        subtitle: Text(
          moveToTrash
              ? 'Files will be moved to your system Trash / Recycle Bin so you can restore them if needed.'
              : 'Files will be permanently erased from disk and cannot be recovered.',
          style: TextStyle(
            fontSize: 11.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: moveToTrash,
        onChanged: onChanged,
      ),
    );
  }
}

/// Visual tone for bottom floating capsule notifications.
enum CapsuleToastTone {
  info,
  success,
  warning,
  error,
}

/// Displays a sleek floating pill/capsule notification centered near the bottom
/// of the window, hugging its text content instead of stretching full-width.
void showCapsuleToast(
  BuildContext context,
  String message, {
  CapsuleToastTone tone = CapsuleToastTone.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF263042) : const Color(0xFF1E293B);
  final borderColor = Colors.white.withValues(alpha: isDark ? 0.14 : 0.10);

  final (IconData defaultIcon, Color accentColor) = switch (tone) {
    CapsuleToastTone.success => (
        Icons.check_circle_rounded,
        const Color(0xFF34D399),
      ),
    CapsuleToastTone.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFFBBF24),
      ),
    CapsuleToastTone.error => (
        Icons.error_rounded,
        const Color(0xFFF87171),
      ),
    CapsuleToastTone.info => (
        Icons.info_rounded,
        const Color(0xFF60A5FA),
      ),
  };

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      hitTestBehavior: HitTestBehavior.translucent,
      dismissDirection: DismissDirection.down,
      duration: duration,
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Material(
              color: bgColor,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.24),
              shape: StadiumBorder(
                side: BorderSide(color: borderColor, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: messenger.hideCurrentSnackBar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon ?? defaultIcon, size: 18, color: accentColor),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
