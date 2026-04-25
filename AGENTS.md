# AGENTS.md — Build Orchestrator Rules

## Deployment Discipline

**NEVER update live services and config files directly.**

All changes must be made to the source files in this repository first, then deployed to the live system using `install.sh`.

This means:
- Source files live in: `systemd/`, `sway-sunshine/`, `sunshine/`, `pipewire/`, `udev/`
- Live config paths are: `~/.config/systemd/user/`, `~/.config/sway-sunshine/`, `~/.config/sunshine/`, `~/.config/pipewire/`
- Always edit the repo files, then run `./install.sh` to copy them to the live system
- This ensures config changes are tracked in git and can be reproduced

## Sudo Discipline

**NEVER run sudo yourself.** If any operation requires sudo privileges, stop and ask the user to run it. Failed sudo attempts can lock the user's account.

This means:
- If you need to install a package with `sudo pacman -S` or `sudo apt install`, tell the user the exact command to run
- If you need to modify system files (e.g., `/etc/udev/rules.d/`, `/etc/systemd/system/`), provide the command and let the user execute it
- Never use `sudo`, `su`, or `pkexec` in any command you run directly

## Project Overview

This repo manages a **headless Sway + Sunshine game streaming** setup. A separate headless Wayland session (Sway) runs dedicated to game streaming, fully isolated from the main desktop. Sunshine captures the headless session and streams via Moonlight.

Key services:
- `sway-sunshine.service` — headless Sway compositor (no physical display)
- `sunshine-headless.service` — Sunshine server pointed at the headless session

## Scripts in `sway-sunshine/`

### `set-resolution.sh`
Called by Sunshine as a **prep-cmd.do** when a client connects. Uses `swaymsg` to set the headless output to match the Moonlight client's resolution/fps via `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, `SUNSHINE_CLIENT_FPS` env vars. Includes a 1s sleep for display mode to settle.

### `reset-resolution.sh`
Called by Sunshine as a **prep-cmd.undo** when a client disconnects. Resets headless output to 1920x1080@60Hz.

### `restore-default-sink.sh`
Restores the host's default audio sink after Sunshine changes it (Sunshine sets `audio_sink` as system default on connect). Uses `systemd-run` to spawn a detached watcher that survives prep-cmd cleanup, polling wpctl for 30s to detect and restore the original default sink.

### `start-steam-game.sh`
Launches a Steam game in the headless Sway session. **Migrates Steam from the main desktop if it's running there.** Handles:
- Graceful shutdown of any existing Steam instance (`steam -shutdown`, wait, force kill)
- Cleanup of Steam IPC files (`~/.steam/steam.pid`, `/tmp/steam_singleton_*`)
- Launch via `swaymsg exec` in the headless session
- Accepts: `<appid>`, `bigpicture`, or `0` (plain Steam)

### `stop-steam-game.sh`
Shuts down Steam in the headless session and cleans up IPC. Used as **prep-cmd.undo** for Steam entries.

> **Note:** `start-steam-game.sh` and `stop-steam-game.sh` are NOT copied by `install.sh`. They must be manually copied to `~/.config/sway-sunshine/` and made executable.

## `apps.json` Format & Conventions

The live config at `~/.config/sunshine/apps.json` uses **Sunshine v2 format** (`"version": 2`).

### Prep-cmd pattern for all games

Every game should have prep-cmd hooks for resolution and audio sink management:

```json
"prep-cmd": [
  {
    "do": "/home/moe/.config/sway-sunshine/restore-default-sink.sh",
    "undo": ""
  },
  {
    "do": "/home/moe/.config/sway-sunshine/set-resolution.sh",
    "undo": "/home/moe/.config/sway-sunshine/reset-resolution.sh"
  }
]
```

- `restore-default-sink.sh`: undo is empty (no need to restore on disconnect)
- `set-resolution.sh`: undo is `reset-resolution.sh` (revert to 1080p)

### Steam entries

Use `start-steam-game.sh` via `detached` instead of raw `steam steam://run/...` commands:

```json
{
  "name": "Game Name",
  "detached": ["/home/moe/.config/sway-sunshine/start-steam-game.sh <appid>"],
  "prep-cmd": [
    {"do": "/home/moe/.config/sway-sunshine/restore-default-sink.sh", "undo": ""},
    {"do": "/home/moe/.config/sway-sunshine/set-resolution.sh", "undo": "/home/moe/.config/sway-sunshine/stop-steam-game.sh"}
  ],
  "auto-detach": true,
  "wait-all": true
}
```

Steam undo uses `stop-steam-game.sh` instead of `reset-resolution.sh` because stopping Steam is the critical cleanup action.

### Desktop entry

The Desktop entry needs prep-cmd hooks with the full resolution pair:

```json
{
  "name": "Desktop",
  "cmd": "",
  "prep-cmd": [
    {"do": "/home/moe/.config/sway-sunshine/restore-default-sink.sh", "undo": ""},
    {"do": "/home/moe/.config/sway-sunshine/set-resolution.sh", "undo": "/home/moe/.config/sway-sunshine/reset-resolution.sh"}
  ]
}
```

### LutrisToSunshine entries

Entries using `lutristosunshine-launch-app.sh` keep their custom launch commands. Add prep-cmd hooks but **do not change the cmd field**. These entries don't use Steam migration, so undo for resolution is empty.

### Entries to leave alone

- **Steam Big Picture (Dual)** — uses gamescope with custom `do-dual.sh` script, different setup
- **Low Res Desktop** — uses raw `xrandr` in detached, no resolution hooks needed
- **Shutdown PC** — system command, no hooks needed

### Duplicate cleanup

When a game has both a LutrisToSunshine entry and a raw `steam steam://run/...` entry with the same UUID, **keep the LutrisToSunshine version and remove the raw steam duplicate**.

## install.sh Behavior

The install script:
- Templates user ID into `set-resolution.sh` and `reset-resolution.sh` (replaces `/run/user/1000/`)
- Does NOT copy `start-steam-game.sh` or `stop-steam-game.sh` — these must be installed manually
- Preserves existing `sunshine.conf` and `apps.json` if they already exist
- Auto-detects DE for udev rule (GNOME vs KDE input isolation)

## KDE Plasma Wayland Compatibility (Updated 2026-04-25)

### Capture Method: wlr

**`capture = wlr` is the working method for KDE Plasma Wayland.** This is the correct and default capture method for this setup.

**How it works:** Sunshine connects to the **headless Sway session** (`WAYLAND_DISPLAY=wayland-1`), NOT to KWin/KDE Plasma. Sway implements `zwlr-screencopy-unstable-v1` natively because it IS a wlroots compositor. The wlr capture path talks directly to Sway's Wayland socket — it never involves KWin at all.

**This is why the setup works on KDE Plasma:** KWin's lack of wlr-screencopy support is irrelevant because Sunshine captures from Sway, not from the KDE desktop session.

**Required setup:**
- `sunshine.conf` must have `capture = wlr` (this is the repo template default — do NOT change to `kms`)
- Headless Sway must be running with `WLR_BACKENDS=headless` and `WLR_RENDERER=gles2`
- `sway-sunshine.service` must set `WLR_DRM_DEVICES` to the correct render node (see Hardware Layout below)



### Cross-GPU DMA-BUF Failure (KMS-specific)

**The cross-GPU DMA-BUF SEGV crash is specific to `capture = kms` mode, NOT `capture = wlr`.** With wlr capture, frames are shared via Wayland/DMA-BUF between Sway and Sunshine in the same session — no cross-device import is needed.

If you ever use `capture = kms` (e.g., for direct DRM capture), you MUST avoid cross-GPU capture+encode:
- If KMS captures from one GPU but the Vulkan encoder runs on a different GPU, cross-device DMA-BUF import fails with SEGV crash → "No video received." This applies to any AMD + NVIDIA combination.
- **Fix for KMS mode:** Restrict Sunshine's Vulkan to only the capture GPU using `VK_ICD_FILENAMES`:
  - **AMD capture GPU:** `Environment=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json`
  - **NVIDIA capture GPU:** `Environment=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json`
This tells Vulkan to only use the capture GPU's driver, preventing the other GPU from being selected for encoding.

### What Does NOT Work on KDE Plasma Wayland

- **Nested Sway EGL** — KWin doesn't allow nested compositors DRM access. `eglQueryDeviceStringEXT(EGL_DRM_DEVICE_FILE_EXT)` returns `EGL_BAD_PARAMETER`. This works on GNOME/Mutter but not KWin. (The headless backend avoids this by using `WLR_BACKENDS=headless`.)
- **Portal capture for headless isolation** — Portal captures the active desktop session, not a separate headless session. Use wlr capture with headless Sway for headless isolation.

### Prep-cmd Standardization

All apps.json entries should use `sway-sunshine/` scripts for prep-cmds:
- `/home/moe/.config/sway-sunshine/set-resolution.sh` (do)
- `/home/moe/.config/sway-sunshine/reset-resolution.sh` (undo for non-Steam)
- `/home/moe/.config/sway-sunshine/stop-steam-game.sh` (undo for Steam)
- `/home/moe/.config/sway-sunshine/restore-default-sink.sh` (do, undo empty)

LutrisToSunshine (`lutristosunshine.py`) has been updated to generate apps.json using `sway-sunshine/` scripts. The old `lutristosunshine-set-resolution.sh` and `lutristosunshine-reset-resolution.sh` in the LutrisToSunshine bin directory are no longer needed for prep-cmds.

### apps.json Cleanup Pattern

When cleaning apps.json:
1. Remove duplicate entries (same UUID) — keep first occurrence
2. Replace all `lutristosunshine-set-resolution.sh` references with `sway-sunshine/set-resolution.sh`
3. For Steam games: use `stop-steam-game.sh` as resolution undo
4. For non-Steam games: use `reset-resolution.sh` as resolution undo
5. Keep `restore-default-sink.sh` entries as-is
