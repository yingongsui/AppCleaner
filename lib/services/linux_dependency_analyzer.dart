import 'dart:io';

import '../models/app_models.dart';
import '../utils/format_utils.dart';
import '../utils/platform_parsers.dart';

/// Analyzes additional libraries/dependencies installed alongside a Linux
/// package (APT/dpkg, Pacman, DNF/rpm, Flatpak) so they can be displayed and
/// selectively uninstalled together with the main application.
class LinuxDependencyAnalyzer {
  /// Finds all additional libraries/dependencies installed with [app] on Linux.
  Future<List<LinuxDependencyPackage>> analyzeDependencies(
    InstalledApp app,
  ) async {
    if (!Platform.isLinux) {
      return [];
    }

    final pkgName = app.linuxPackageName ?? app.identifier;
    if (pkgName.isEmpty) return [];

    switch (app.installSource) {
      case InstallSource.aptDpkg:
        return _analyzeAptDependencies(pkgName);
      case InstallSource.pacman:
        return _analyzePacmanDependencies(pkgName);
      case InstallSource.dnfRpm:
        return _analyzeDnfDependencies(pkgName);
      case InstallSource.flatpak:
        return _analyzeFlatpakRuntimes(app.identifier);
      default:
        if (await _hasCommand('apt-get')) {
          return _analyzeAptDependencies(pkgName);
        } else if (await _hasCommand('pacman')) {
          return _analyzePacmanDependencies(pkgName);
        } else if (await _hasCommand('dnf')) {
          return _analyzeDnfDependencies(pkgName);
        }
        return [];
    }
  }

  Future<List<LinuxDependencyPackage>> _analyzeAptDependencies(
    String packageName,
  ) async {
    final historyInstalled = await _parseAptHistoryCompanions(packageName);
    final removableOrphans = <String>{};

    try {
      final simResult = await Process.run(
        'apt-get',
        ['-s', 'autoremove', packageName],
        environment: {'LC_ALL': 'C'},
      );
      if (simResult.exitCode == 0) {
        final output = simResult.stdout as String;
        for (final line in output.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Remv ')) {
            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final pkg = parts[1].split(':').first.trim();
              if (pkg != packageName && pkg.isNotEmpty) {
                removableOrphans.add(pkg);
              }
            }
          }
        }
      }
    } catch (_) {}

    final directDeps = <String>{};
    try {
      final depRes = await Process.run(
        'apt-cache',
        ['depends', packageName],
        environment: {'LC_ALL': 'C'},
      );
      if (depRes.exitCode == 0) {
        for (final line in (depRes.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Depends:') ||
              trimmed.startsWith('Recommends:')) {
            final depName = trimmed
                .split(':')
                .skip(1)
                .join(':')
                .trim()
                .replaceAll('<', '')
                .replaceAll('>', '');
            if (depName.isNotEmpty &&
                !depName.startsWith('libc6') &&
                !depName.startsWith('libgcc') &&
                !depName.startsWith('libstdc++')) {
              directDeps.add(depName.split(':').first);
            }
          }
        }
      }
    } catch (_) {}

    final autoPkgs = <String>{};
    try {
      final autoRes = await Process.run('apt-mark', ['showauto']);
      if (autoRes.exitCode == 0) {
        for (final line in (autoRes.stdout as String).split('\n')) {
          final p = line.trim().split(':').first;
          if (p.isNotEmpty) autoPkgs.add(p);
        }
      }
    } catch (_) {}

    final candidatePackages = <String>{
      ...removableOrphans,
      ...historyInstalled,
      ...directDeps.where((d) => autoPkgs.contains(d)),
    }..remove(packageName);

    if (candidatePackages.isEmpty) return [];

    final metaMap = await _fetchDpkgMetadata(candidatePackages.toList());
    final results = <LinuxDependencyPackage>[];

    for (final dep in candidatePackages) {
      final meta = metaMap[dep];
      if (meta == null) continue;

      final isOrphanOnRemove = removableOrphans.contains(dep);
      final inHistory = historyInstalled.contains(dep);
      final isAuto = autoPkgs.contains(dep) || isOrphanOnRemove || inHistory;

      List<String> otherReverseDeps = [];
      if (!isOrphanOnRemove) {
        otherReverseDeps = await _getInstalledReverseDepsApt(
          dep,
          excludePkg: packageName,
          excludeSet: removableOrphans,
        );
      }

      final exclusivelyRequired =
          isOrphanOnRemove || otherReverseDeps.isEmpty;

      results.add(
        LinuxDependencyPackage(
          packageName: dep,
          version: meta.version,
          sizeBytes: meta.sizeBytes,
          packageManager: 'apt',
          isAutoInstalled: isAuto,
          isExclusivelyRequired: exclusivelyRequired,
          installedTogetherInHistory: inHistory,
          requiredByOthers: otherReverseDeps,
          description: meta.description,
          selected: isAuto && exclusivelyRequired,
        ),
      );
    }

    results.sort((a, b) {
      if (a.isSafeToRemove != b.isSafeToRemove) {
        return a.isSafeToRemove ? -1 : 1;
      }
      if (a.installedTogetherInHistory != b.installedTogetherInHistory) {
        return a.installedTogetherInHistory ? -1 : 1;
      }
      return b.sizeBytes.compareTo(a.sizeBytes);
    });

    return results;
  }

  Future<Set<String>> _parseAptHistoryCompanions(String targetPackage) async {
    final file = File('/var/log/apt/history.log');
    if (!await file.exists()) return {};
    try {
      final content = await file.readAsString();
      return PlatformParsers.parseAptHistoryCompanions(content, targetPackage);
    } catch (_) {
      return {};
    }
  }

  Future<
      Map<String, ({String version, int sizeBytes, String description})>>
      _fetchDpkgMetadata(List<String> packages) async {
    final result =
        <String, ({String version, int sizeBytes, String description})>{};
    if (packages.isEmpty) return result;
    try {
      final res = await Process.run('dpkg-query', [
        '-W',
        r'-f=${Package}\t${Version}\t${Installed-Size}\t${binary:Summary}\n',
        ...packages,
      ]);
      final stdoutStr = res.stdout as String;
      for (final line in stdoutStr.split('\n')) {
        final parts = line.trim().split('\t');
        if (parts.length >= 3) {
          final pkg = parts[0].split(':').first.trim();
          final ver = parts[1].trim();
          final sizeKb = int.tryParse(parts[2].trim()) ?? 0;
          final desc = parts.length >= 4 ? parts[3].trim() : '';
          if (ver.isNotEmpty) {
            result[pkg] = (
              version: ver,
              sizeBytes: sizeKb * 1024,
              description: desc,
            );
          }
        }
      }
    } catch (_) {}
    return result;
  }

  Future<List<String>> _getInstalledReverseDepsApt(
    String depPackage, {
    required String excludePkg,
    required Set<String> excludeSet,
  }) async {
    final others = <String>[];
    try {
      final res = await Process.run(
        'apt-cache',
        ['rdepends', '--installed', depPackage],
        environment: {'LC_ALL': 'C'},
      );
      if (res.exitCode == 0) {
        final lines = (res.stdout as String).split('\n').skip(2);
        for (final line in lines) {
          final pkg = line.trim().replaceFirst('|', '').trim().split(':').first;
          if (pkg.isNotEmpty &&
              pkg != depPackage &&
              pkg != excludePkg &&
              !excludeSet.contains(pkg)) {
            if (!others.contains(pkg)) others.add(pkg);
          }
        }
      }
    } catch (_) {}
    return others;
  }

  Future<List<LinuxDependencyPackage>> _analyzePacmanDependencies(
    String packageName,
  ) async {
    final results = <LinuxDependencyPackage>[];
    try {
      final infoRes = await Process.run(
        'pacman',
        ['-Qi', packageName],
        environment: {'LC_ALL': 'C'},
      );
      if (infoRes.exitCode != 0) return [];

      final directDeps = <String>[];
      for (final line in (infoRes.stdout as String).split('\n')) {
        if (line.startsWith('Depends On')) {
          final rhs = line.split(':').skip(1).join(':').trim();
          if (rhs != 'None') {
            for (final token in rhs.split(RegExp(r'\s+'))) {
              final clean = token.split(RegExp(r'[<>=]')).first.trim();
              if (clean.isNotEmpty) directDeps.add(clean);
            }
          }
        }
      }

      for (final dep in directDeps) {
        final depRes = await Process.run(
          'pacman',
          ['-Qi', dep],
          environment: {'LC_ALL': 'C'},
        );
        if (depRes.exitCode != 0) continue;

        String version = '';
        String description = '';
        int sizeBytes = 0;
        bool isAuto = false;
        final requiredBy = <String>[];

        for (final line in (depRes.stdout as String).split('\n')) {
          if (line.startsWith('Version')) {
            version = line.split(':').skip(1).join(':').trim();
          } else if (line.startsWith('Description')) {
            description = line.split(':').skip(1).join(':').trim();
          } else if (line.startsWith('Installed Size')) {
            sizeBytes = FormatUtils.parseHumanSize(
              line.split(':').skip(1).join(':').trim(),
            );
          } else if (line.startsWith('Install Reason')) {
            isAuto = line.toLowerCase().contains('dependency');
          } else if (line.startsWith('Required By')) {
            final rhs = line.split(':').skip(1).join(':').trim();
            if (rhs != 'None') {
              requiredBy.addAll(
                rhs
                    .split(RegExp(r'\s+'))
                    .where((p) => p.isNotEmpty && p != packageName),
              );
            }
          }
        }

        final exclusive = requiredBy.isEmpty;
        if (isAuto || exclusive) {
          results.add(
            LinuxDependencyPackage(
              packageName: dep,
              version: version,
              sizeBytes: sizeBytes,
              packageManager: 'pacman',
              isAutoInstalled: isAuto,
              isExclusivelyRequired: exclusive,
              requiredByOthers: requiredBy,
              description: description,
              selected: isAuto && exclusive,
            ),
          );
        }
      }
    } catch (_) {}
    return results;
  }

  Future<List<LinuxDependencyPackage>> _analyzeDnfDependencies(
    String packageName,
  ) async {
    final results = <LinuxDependencyPackage>[];
    try {
      final res = await Process.run(
        'dnf',
        ['repoquery', '--installed', '--requires', '--resolve', packageName],
        environment: {'LC_ALL': 'C'},
      );
      if (res.exitCode != 0) return [];
      for (final line in (res.stdout as String).split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        results.add(
          LinuxDependencyPackage(
            packageName: trimmed,
            version: '',
            sizeBytes: 0,
            packageManager: 'dnf',
            isAutoInstalled: true,
            isExclusivelyRequired: false,
            description: 'RPM dependency library',
            selected: false,
          ),
        );
      }
    } catch (_) {}
    return results;
  }

  Future<List<LinuxDependencyPackage>> _analyzeFlatpakRuntimes(
    String appId,
  ) async {
    final results = <LinuxDependencyPackage>[];
    try {
      final res = await Process.run(
        'flatpak',
        ['info', appId],
        environment: {'LC_ALL': 'C'},
      );
      if (res.exitCode == 0) {
        for (final line in (res.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Runtime:')) {
            final runtime = trimmed.substring('Runtime:'.length).trim();
            if (runtime.isNotEmpty) {
              results.add(
                LinuxDependencyPackage(
                  packageName: runtime,
                  version: 'Flatpak Runtime',
                  sizeBytes: 0,
                  packageManager: 'flatpak',
                  isAutoInstalled: true,
                  isExclusivelyRequired: false,
                  description:
                      'Flatpak runtime environment (runs flatpak uninstall --unused after app removal)',
                  selected: true,
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
    return results;
  }

  Future<bool> _hasCommand(String cmd) async {
    try {
      final res = await Process.run('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
