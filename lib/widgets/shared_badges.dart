import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';

/// Shared gradient initial avatar for installed applications.
class AppAvatar extends StatelessWidget {
  final String name;
  final bool isSystem;
  final double size;
  final double borderRadius;
  final double fontSize;

  const AppAvatar({
    super.key,
    required this.name,
    required this.isSystem,
    this.size = 40,
    this.borderRadius = 10,
    this.fontSize = 17,
  });

  @override
  Widget build(BuildContext context) {
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
    final Color bg;
    final Color fg;
    if (item.isRegistryKey) {
      bg = Colors.deepPurple.withValues(alpha: 0.16);
      fg = Colors.deepPurple.shade800;
    } else if (item.isCacheLike) {
      bg = Colors.amber.withValues(alpha: 0.2);
      fg = Colors.amber.shade900;
    } else {
      bg = Colors.teal.withValues(alpha: 0.15);
      fg = Colors.teal.shade800;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: dependency.isSafeToRemove
            ? Colors.teal.withValues(alpha: 0.15)
            : Colors.amber.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        dependency.safetyBadgeText,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: dependency.isSafeToRemove
              ? Colors.teal.shade800
              : Colors.amber.shade900,
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(copiedSnackMessage),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
