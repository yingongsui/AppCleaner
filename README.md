# AppCleaner

Cross-platform desktop application uninstaller, Android-style app data/cache resetter, and leftover cleaner built with Flutter for **macOS (Apple Silicon arm64)**, **Linux (64-bit amd64)**, and **Windows (64-bit x64)**.

## Key Features

1. **Installed App Discovery & Origin Classification**
   - Scans installed applications and clearly separates **User Apps** from protected **System Apps**.
   - Supports macOS `.app` bundles (App Store, Homebrew Cask, `/Applications`, `/System/Applications`), Linux `.desktop` / APT / Pacman / DNF / Flatpak / Snap packages, and Windows Win32 Registry & MSIX/Appx packages.

2. **Android-Style Data & Cache Clearing (Without Uninstalling)**
   - **Clear Cache Only**: Removes runtime caches, logs, and saved window state while preserving accounts, preferences, and app binaries.
   - **Clear Selected Data / Reset App**: Resets an application to a freshly installed state by clearing its data, config, containers, and Windows Registry keys while keeping the binary intact.

3. **Deep Uninstall, Leftover Scanner & Linux Dependency Removal**
   - **App Uninstall**: Removes the application alongside all selected data, config, and Windows Registry leftovers (with automatic `.reg` backup before deletion).
   - **Linux Additional Libraries Cleanup**: Analyzes `/var/log/apt/history.log`, `apt-get -s autoremove`, `pacman -Qi`, `dnf`, and Flatpak runtimes to detect and selectively uninstall auto-installed libraries that are no longer needed by any other installed package.
   - **Orphaned Leftovers Scanner**: Cross-references user directories and Windows Registry hives against currently installed apps to identify and clean residuals left behind by previously uninstalled apps.

## Cloud Release Workflow (GitHub Actions)

Push a version tag (`v*`) or run the workflow manually in GitHub Actions to build and publish:
- `AppCleaner-<version>-macos-arm64.dmg` (Apple Silicon M-series)
- `AppCleaner-<version>-linux-amd64.deb` (64-bit Debian/Ubuntu)
- `AppCleaner-<version>-windows-x64-setup.exe` (64-bit Windows installer)

```bash
git tag v1.0.0
git push origin v1.0.0
```
