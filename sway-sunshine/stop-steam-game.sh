#!/bin/bash
# Shuts down ALL Steam processes system-wide, cleans up IPC, then restarts
# Steam on the main desktop (wayland-0).
#
# This is used as prep-cmd.undo for Steam entries in apps.json.
# Steam on the main desktop IS restarted after the headless session's Steam
# is fully stopped.
#
# Uses systemd-run --user --scope to launch Steam in the user session context,
# which works on any desktop environment (KDE, GNOME, Sway, etc.).

LOG="$HOME/.config/sway-sunshine/stop-steam-game.log"
touch "$LOG" 2>/dev/null
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

log "=== stop-steam-game.sh started ==="

# --- Shut down ALL Steam processes (including children) ---
log "Shutting down all Steam processes..."
pkill -TERM -f "steam" 2>/dev/null

# Wait for all Steam-related processes to exit
log "Waiting for Steam processes to exit..."
for i in $(seq 1 30); do
    if ! pgrep -f "steam" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Force kill any remaining Steam processes
if pgrep -f "steam" > /dev/null 2>&1; then
    log "Some Steam processes still running, force killing..."
    pkill -KILL -f "steam" 2>/dev/null
    sleep 2
fi

# Double-check everything is gone
if pgrep -f "steam" > /dev/null 2>&1; then
    log "WARNING: Steam processes still running after SIGKILL"
else
    log "All Steam processes terminated."
fi

# --- Clean up IPC ---
log "Cleaning up IPC files..."
rm -f ~/.steam/steam.pid 2>/dev/null
rm -f /tmp/steam_singleton_* 2>/dev/null

# --- Restart Steam on the main desktop ---
log "Restarting Steam on main desktop (wayland-0)..."
if command -v systemd-run >/dev/null 2>&1; then
    log "Using systemd-run to launch Steam..."
    systemd-run --user --scope --unit=steam-restore-wayland-0 steam &
    log "Steam launch command sent via systemd-run."
else
    log "ERROR: systemd-run not found. Cannot restart Steam."
fi

log "=== stop-steam-game.sh finished ==="
