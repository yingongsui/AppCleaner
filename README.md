# AppCleaner

Cross-platform desktop application uninstaller, Android-style app data/cache resetter, and leftover cleaner built with Flutter for **macOS (Apple Silicon arm64)**, **Linux (64-bit amd64)**, and **Windows (64-bit x64)**.

- **Application ID**: `com.yin.appcleaner`
- **Local Configuration & History**: `settings.json` and `history.json` stored under `~/Library/Application Support/AppCleaner/` (macOS), `~/.local/share/AppCleaner/` (Linux), or `%APPDATA%\AppCleaner\` (Windows)

## Key Features

1. **Installed App Discovery, Real Icons & Self-Lock Protection**
   - Scans installed applications with real native icons (`NSWorkspace` on macOS, freedesktop icon themes on Linux, `ExtractAssociatedIcon` on Windows) and classifies **User Apps** vs protected **System Apps**.
   - Inspects **1-level vendor subfolders** (e.g. `Softdeluxe/Free Download Manager`, `Google/Chrome`) and strips version/channel suffixes (e.g. `LyX-2.4`, `GIMP-2.10`) for accurate app data linking.
   - Built-in **Self-Lock** protects `AppCleaner` itself from accidental termination, reset, or uninstallation.

2. **Android-Style Data & Cache Clearing (Without Uninstalling)**
   - **Clear Cache Only**: Removes runtime caches, logs, and saved state while preserving accounts, preferences, and app binaries.
   - **Clear Selected Data / Reset App**: Resets an application to a freshly installed state by clearing data, preferences (including macOS `cfprefsd` cache flush), containers, and Windows Registry keys while keeping the binary intact.

3. **Deep Uninstall, Safe Trash Mode, Orphaned Leftover Scanner & Linux Dependency Removal**
   - **Recoverable System Trash by Default**: Every cleanup and uninstall confirmation dialog defaults to moving files to the native OS Trash / Recycle Bin (`~/.Trash` on macOS, `gio trash` / Freedesktop XDG Trash on Linux, Recycle Bin on Windows) with a toggle for permanent deletion.
   - **Linux Additional Libraries Cleanup**: Analyzes `/var/log/apt/history.log`, `apt-get -s autoremove`, `pacman -Qi`, `dnf`, and Flatpak runtimes to detect and selectively uninstall exclusive auto-installed dependency libraries.
   - **Orphaned Leftovers Scanner**: Cross-references user directories, CLI binaries, installed system packages, and Windows Registry hives; supports right-click actions to **Associate with Installed App** or **Add to Whitelist**.
   - **Settings & Persistent Activity History**: Manage scan depth, safety defaults, custom & built-in whitelists, manual app associations, and persistent cleanup logs.

## Cloud Release Workflow (GitHub Actions)

Push a version tag (`v*`) or run the workflow manually in GitHub Actions to verify (`flutter analyze` + `flutter test`), build, and publish:
- `AppCleaner-<version>-macos-arm64.dmg` (Apple Silicon M-series)
- `AppCleaner-<version>-linux-amd64.deb` (64-bit Debian/Ubuntu)
- `AppCleaner-<version>-windows-x64-setup.exe` (64-bit Windows installer)

```bash
git tag v1.1.0
git push origin v1.1.0
```
