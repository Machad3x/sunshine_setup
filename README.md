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
- **Troubleshooting & Utility Actions**:
  - **Error 503 Fix**: Applies `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` environment tweak for KWin Wayland permissions.
  - **Firewall Setup**: Automatically detects `firewalld` or `ufw` and opens necessary network ports for streaming and mDNS discovery.
  - **Clean Uninstallation**: Removes virtual monitor scripts, systemd post-execution hooks, and Sunshine application configurations.

---

## 🐧 Supported Distributions

| Distribution Type | Supported Systems / Distros | Allowed Installation Method |
| :--- | :--- | :--- |
| **Traditional Systems** | Fedora, Arch Linux, CachyOS, Ubuntu, Debian | Native Package **or** Flatpak |
| **Immutable / Atomic** | Bazzite, Silverblue, Kinoite, SteamOS, Bluefin, Aurora, openSUSE MicroOS | **Flatpak Only** (`--system` / `--user`) |

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
| `./sunshine-setup.sh vmon` | Configure KDE Plasma virtual monitor automation. |
| `./sunshine-setup.sh 503` | Apply the Moonlight / KWin permission fix for Error 503. |
| `./sunshine-setup.sh firewall` | Configure firewall rules for `firewalld` or `ufw`. |
| `./sunshine-setup.sh remove` | Remove virtual monitor configuration and clean up scripts. |
| `./sunshine-setup.sh --help` | Display script usage notes and options. |

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

---

## 📄 License

Distributed under the MIT License. Feel free to modify and adapt for custom system images or distribution post-install routines.