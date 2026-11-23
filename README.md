# AppCleaner

Cross-platform desktop application uninstaller, Android-style app data/cache resetter, and leftover cleaner built with Flutter for **macOS (Apple Silicon arm64)**, **Linux (64-bit amd64)**, and **Windows (64-bit x64)**.

- **Application ID**: `com.yin.appcleaner`
- **History Storage**: `history.json` stored under `~/Library/Application Support/AppCleaner/` (macOS), `~/.local/share/AppCleaner/` (Linux), or `%APPDATA%\AppCleaner\` (Windows)

## Key Features

1. **Installed App Discovery, Real Icons & Self-Lock Protection**
   - Scans installed applications with real native icons (`NSWorkspace` on macOS, freedesktop icon themes on Linux, `ExtractAssociatedIcon` on Windows) and classifies **User Apps** vs protected **System Apps**.
   - Built-in **Self-Lock** protects `AppCleaner` itself from accidental termination, reset, or uninstallation.

2. **Android-Style Data & Cache Clearing (Without Uninstalling)**
   - **Clear Cache Only**: Removes runtime caches, logs, and saved state while preserving accounts, preferences, and app binaries.
   - **Clear Selected Data / Reset App**: Resets an application to a freshly installed state by clearing data, preferences (including macOS `cfprefsd` cache flush), containers, and Windows Registry keys while keeping the binary intact.

3. **Deep Uninstall, Orphaned Leftover Scanner & Linux Dependency Removal**
   - **App Uninstall**: Removes the application alongside selected data, config, macOS `cfprefsd` preferences, and Windows Registry leftovers (with automatic `.reg` backup and critical-hive safety guard).
   - **Linux Additional Libraries Cleanup**: Analyzes `/var/log/apt/history.log`, `apt-get -s autoremove`, `pacman -Qi`, `dnf`, and Flatpak runtimes to detect and selectively uninstall auto-installed dependency libraries not needed by other packages.
   - **Orphaned Leftovers Scanner**: Cross-references user directories and Windows Registry hives against currently installed apps to detect and remove residual files left by previously uninstalled apps.
   - **Persistent Activity History**: Saves all cleaning and uninstallation logs to disk and restores them on relaunch.

## Cloud Release Workflow (GitHub Actions)

Push a version tag (`v*`) or run the workflow manually in GitHub Actions to verify (`flutter analyze` + `flutter test`), build, and publish:
- `AppCleaner-<version>-macos-arm64.dmg` (Apple Silicon M-series)
- `AppCleaner-<version>-linux-amd64.deb` (64-bit Debian/Ubuntu)
- `AppCleaner-<version>-windows-x64-setup.exe` (64-bit Windows installer)

```bash
git tag v1.0.0
git push origin v1.0.0
```
