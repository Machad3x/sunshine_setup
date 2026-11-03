> **Note:** This project was vibe-coded with AI assistance.

# Sunshine Setup Script

Automated installation and configuration script for [Sunshine](https://github.com/LizardByte/Sunshine) (self-hosted game stream host) and virtual monitor setup tailored for KDE Plasma (Wayland).

Ported and enhanced from the Bazzite `setup-sunshine` ujust recipe and virtual monitor automation scripts.

---

## 🚀 Features

- **Multi-distro Native Support**:
  - **Fedora**: Installed via COPR (`lizardbyte/stable`).
  - **Arch Linux**: Installed via AUR (`sunshine-bin`) using `yay` or `paru`.
  - **CachyOS**: Installed via official repositories (`pacman -S sunshine`).
  - **Ubuntu / Debian**: Automatically fetches and installs compatible upstream `.deb` releases.
- **Immutable System Protection**:
  - Full support for **Fedora Silverblue**, **Kinoite**, **Bazzite**, **Bluefin**, **Aurora**, **SteamOS**, **openSUSE MicroOS**, `bootc`, and other immutable variants.
  - Native package manager execution (`dnf`, `pacman`, `apt`) is **strictly prevented** on immutable systems.
  - Automatic fallback to **Flatpak** installation.
- **Flexible Flatpak Installation**:
  - Supports installing Sunshine via Flatpak with custom scope selection: `--system` (global) or `--user` (per-user).
- **Virtual Monitor Integration**:
  - Automated virtual display provisioning for KDE Plasma (Wayland) using `krfb-virtualmonitor` and `kscreen-doctor`.
  - Configures dynamic display resolution and frame-rate matching (SUNSHINE_CLIENT_WIDTH / HEIGHT / FPS).
  - Saves the previously enabled displays and the original Sunshine `output_name`; restores them on stop and rolls back failed startup.
- **Troubleshooting & Utility Actions**:
  - **Error 503 Fix**: Adds `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` in a dedicated environment file; `503-reset` removes the setting.
  - **Firewall Setup**: Automatically detects `firewalld` or `ufw` and opens necessary network ports for streaming and mDNS discovery, optionally restricted to an IPv4/IPv6 CIDR.
  - **Clean Uninstallation**: Removes virtual monitor scripts, systemd post-execution hooks, and Sunshine application configurations.

---

## 🐧 Supported Distributions

| Distribution Type | Supported Systems / Distros | Allowed Installation Method |
| :--- | :--- | :--- |
| **Traditional Systems** | Fedora, Arch Linux, CachyOS, Ubuntu, Debian | Native Package **or** Flatpak |
| **Immutable / Atomic** | Bazzite, Silverblue, Kinoite, SteamOS, Bluefin, Aurora, openSUSE MicroOS | **Flatpak Only** (`--system` / `--user`) |

The installer reads `/etc/os-release`: it prefers the exact distribution `ID`, then checks `ID_LIKE` from left to right and uses the first supported family. Unknown IDs are not matched by substring.

---

## 🛠️ System Requirements

### General Requirements
- **Standard User**: Run the script as a regular non-root user (avoid `sudo bash ...`). The script prompts for elevated privileges (`sudo`) only when strictly required.

### Virtual Monitor Requirements (Option 2)
- **Desktop Environment**: **KDE Plasma 6 (Wayland)**.
- **Required Packages**:
  - `krfb-virtualmonitor` (provided by `krfb`)
  - `kscreen-doctor` (provided by `libkscreen` / `kscreen`)
  - `jq`
- *Immutable Systems Note*: The script checks for these host binaries. If missing, install them via OSTree layering and reboot:
  ```bash
  rpm-ostree install krfb kscreen jq
  sudo systemctl reboot
  ```

---

## 📋 Installation & Usage

Make the script executable before running:

```bash
chmod +x sunshine-setup.sh
```

### 1. Interactive Mode
Run the script without arguments to open the interactive selection menu:

```bash
./sunshine-setup.sh
```

### 2. Direct Command Usage (CLI)

| Command | Description |
| :--- | :--- |
| `./sunshine-setup.sh install` | Interactive installation prompt. |
| `./sunshine-setup.sh install --flatpak-system` | Force Flatpak installation (System-wide / `--system`). |
| `./sunshine-setup.sh install --flatpak-user` | Force Flatpak installation (Per-user / `--user`). |
| `./sunshine-setup.sh install --native` | Force native package installation (Blocked on immutable systems). |
| `./sunshine-setup.sh virtual-monitor` | Open the Virtual Monitor menu to add or remove its configuration. |
| `./sunshine-setup.sh vmon` | Add/configure KDE Plasma virtual monitor automation directly. |
| `./sunshine-setup.sh remove` | Remove the virtual monitor configuration directly. |
| `./sunshine-setup.sh fixes` | Open the Error 503 menu to apply or revert the fix. |
| `./sunshine-setup.sh 503` | Apply the Error 503 fix directly. |
| `./sunshine-setup.sh 503-reset` | Revert the Error 503 fix directly. |
| `./sunshine-setup.sh firewall` | Configure firewall rules for `firewalld` or `ufw`. |
| `./sunshine-setup.sh --help` | Display script usage notes and options. |

The interactive menu groups related actions under **Virtual Monitor** (add/remove) and **Error 503 Fixes** (apply/revert). Feature implementations and shared mode selection are split into the files under `modules/`, which are loaded by the main script.

---

## 🖥️ Virtual Monitor Setup Instructions

To enable dynamic virtual resolution streaming with Moonlight:

1. Execute the virtual monitor setup:
   ```bash
   ./sunshine-setup.sh vmon
   ```
2. Open the Sunshine Web UI in your browser: `https://localhost:47990`
3. Navigate to **Configuration > Audio/Video**.
4. Set **Capture Method** to **`KWin Screencast`**.
5. Save changes and restart the Sunshine service:
   - **For Flatpak**: `systemctl --user restart app-dev.lizardbyte.app.Sunshine`
   - **For Native**: `systemctl --user restart sunshine`

The script remembers which physical displays were enabled before the virtual display started and restores those displays and the previous `output_name` setting when Sunshine stops. If startup fails, it attempts the same rollback.

---

## 🛡️ Firewall Configuration

Sunshine requires specific ports to operate. Run the standalone firewall helper to automatically detect your active firewall and apply rules:

```bash
./sunshine-setup.sh firewall
```

**Configured Ports:**
- **TCP**: `47984`, `47989`, `48010` (Optional: `47990` for Web UI access over LAN)
- **UDP**: `47998`, `47999`, `48000`, `48002`
- **mDNS**: `5353/udp` (for automatic Moonlight network discovery)

The firewall setup asks whether to limit rules to a source CIDR (for example `192.168.1.0/24` or `fd00::/64`). Leave the input blank to keep the rules open to any source. Exposing the Web UI port is separately optional. Existing unrestricted rules are not removed, so check the current firewall rules before relying on a new CIDR restriction.

---

## 📄 License

Distributed under the MIT License. Feel free to modify and adapt for custom system images or distribution post-install routines.