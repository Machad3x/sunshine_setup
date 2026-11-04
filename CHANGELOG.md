# Changelog

## [3.1.1] - 2026-11-04

### Fixed
- CIDR validation now rejects trailing dots and leading zeros (`1.2.3.4./24`, `010.1.1.1/24`, `1.2.3.4/024`), which were forwarded to `firewalld`/`ufw` as-is.
- The service menu no longer raises a bash arithmetic error when a choice with a leading zero (for example `08`) is entered.
- `install --native` now fails with a clear message on distributions without a native method instead of falsely reporting a successful installation.
- The Hyprland virtual-monitor backend keeps `apps.json` file permissions when updating its app entry and registers temporary files for cleanup on interruption.

### Added
- Regression tests for the stricter CIDR forms, leading-zero menu input, the native-install guard and the Hyprland `apps.json` permission preservation.

## [3.1.0] - 2026-11-04

### Fixed
- KDE virtual-monitor setup now works on unsupported distributions when the host tools are installed and Sunshine is provided by Flatpak.
- Virtual-monitor removal no longer fails when `apps.json` is valid but has no `apps` key.
- KDE and Hyprland hooks no longer store stale session variables (`HYPRLAND_INSTANCE_SIGNATURE`, `WAYLAND_DISPLAY`, ...) in `apps.json`; they are resolved at runtime.
- `native_unit` no longer mistakes the Flatpak unit in `~/.config/systemd/user` for a native installation.
- The unsupported-distribution warning is no longer printed twice in the interactive install flow.
- The unsupported-distribution warning now lists the host packages required by the virtual monitor and states that they are not installed automatically.
- The firewall detector no longer requests sudo to probe ufw when firewalld is already active.
- Downloaded `.deb` files are validated with `dpkg-deb` before installation.

### Changed
- Virtual-monitor helper scripts are installed in `~/.local/bin` instead of `/usr/local/bin`, which also works on immutable systems and matches the Hyprland backend.
- Flatpak hooks forward client geometry with `--env=VAR` pass-through; the KDE hook resolves Wayland/DBus values at runtime.
- Flatpak installation hints now distinguish `rpm-ostree`, `transactional-update` and generic package managers.
- The KDE virtual-monitor backend now requires an explicit Wayland session.

### Added
- KDE virtual-monitor regression tests (`tests/kde.sh`).
- CI workflow running bash syntax checks, ShellCheck and the test suite.

## [3.0.2] - 2026-11-04

### Fixed
- Fixed KDE virtual-monitor startup on KScreen versions that report a connected virtual output with `enabled: null`.
- Improved the startup error message when the virtual output is missing or disconnected.

## [3.0.1] - 2026-11-03

### Fixed
- Allowed Flatpak installation on unsupported distributions while keeping native package installation disabled.

## [3.0.0] - 2026-11-03

### Added
- Added a Hyprland virtual-monitor backend alongside the KDE Plasma backend.
- Added runtime creation and cleanup of Hyprland headless outputs and restoration of physical display configuration.
- Added support for Flatpak installations on immutable systems.

### Changed
- Organized the KDE and Hyprland virtual-monitor implementations into separate backends.
