# Changelog

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
