# Changelog

## [Unreleased]

### Fixed
- The script now fails with a clear message when `/etc/os-release` is missing or unreadable instead of aborting on the `source` command.
- The Error 503 fix reports a clear error when its environment file cannot be written instead of aborting without a message.
- Firewall setup now applies every remaining rule when one `firewall-cmd`/`ufw` call fails, prints a failure summary and exits non-zero instead of dying mid-loop.
- Flatpak installation no longer creates an empty `sunshine.conf` when Sunshine never started; it polls for 10 s (0.5 s interval) and tells the user to start Sunshine before configuring a virtual monitor.
- The KDE virtual-monitor drop-in quotes the `ExecStopPost` path, so a `$HOME` containing spaces no longer breaks the systemd unit.
- `install` rejects unknown flags with exit code 2 instead of silently opening the interactive menu; `service --native` / `service --flatpak` now honor the scope and skip mode detection.
- Ubuntu release detection: use a well-formed `VERSION_ID` directly, map the missing codenames (24.10 oracular, 26.04 resolute, 26.10 stonking) and add 25.04/25.10 to the `.deb` fallback chain.
- Without `jq`, parsing the latest release tag no longer requires GNU grep PCRE support.
- Removal no longer rewrites `apps.json` or prints "Entry removed" when no virtual-monitor entry existed (both backends).
- The script bootstrap no longer depends on `dirname` being in `PATH`.

### Changed
- The Virtual Monitor menu distinguishes "not configured" from "cannot check" when `jq` is not installed.
- "Sunshine is not installed" guidance now names the equivalent CLI command, so it is correct for direct actions (`service`, `repair`, `vmon`) as well as for the menu.
- The Hyprland `flock` error now names the `util-linux` package that provides it.
- KDE virtual-monitor hooks are now standalone files under `modules/vmon/kde/` installed with `install -m`, mirroring the Hyprland backend and bringing them under ShellCheck/CI; previously they were embedded heredocs.
- The VNC password passed to `krfb-virtualmonitor` is exactly 8 characters, matching the protocol limit instead of a longer value krfb truncates.
- Native and Flatpak startup repair share one implementation (`apply_startup_fix`), and the service menu reuses `choose()` (which fixes leading-zero choices like `08`).
- `debian_native_ok` expresses its documented rule as a single test, and `native_unit` no longer probes system paths for Flatpak-generated units (dead code; behavior unchanged).
- Shared helpers moved to `modules/common.sh` (`apps_conf_paths`, `vmon_write_app`, `vmon_remove_app`, `ubuntu_version`, `choose`, `ask_yes_no`); install detection is cached per run and invalidated by the installers; hook/poll loops no longer spawn `seq`.

### Added
- `tests/cli-smoke.sh`: end-to-end CLI suite that runs the real script in a sandboxed HOME with controlled PATHs and a `bwrap`-isolated `/etc`; `tests/run.sh` invokes it when not running as root.
- Unit coverage for the Ubuntu release mapping, Error 503 refusal/legacy reset, unwritable-directory protection, service scope selection, the unknown install flag, the native-install guard, and hook file modes/permissions.
- CI now also runs the test suite in bash 4.4 and 5.0 container jobs.

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
