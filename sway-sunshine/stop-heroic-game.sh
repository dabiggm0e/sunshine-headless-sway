#!/bin/bash
# Kills ALL Heroic processes system-wide.
#
# This is used as prep-cmd.undo for Heroic entries in apps.json.
# Uses pkill -f "heroic" for broad process matching.

LOG="$HOME/.config/sway-sunshine/stop-heroic-game.log"
touch "$LOG" 2>/dev/null
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

log "=== stop-heroic-game.sh started ==="

# --- Shut down ALL Heroic processes (including children) ---
log "Shutting down all Heroic processes..."
pkill -TERM -f "heroic" 2>/dev/null

# Wait for all Heroic-related processes to exit
log "Waiting for Heroic processes to exit..."
for i in $(seq 1 30); do
    if ! pgrep -f "heroic" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Force kill any remaining Heroic processes
if pgrep -f "heroic" > /dev/null 2>&1; then
    log "Some Heroic processes still running, force killing..."
    pkill -KILL -f "heroic" 2>/dev/null
    sleep 2
fi

# Double-check everything is gone
if pgrep -f "heroic" > /dev/null 2>&1; then
    log "WARNING: Heroic processes still running after SIGKILL"
else
    log "All Heroic processes terminated."
fi

log "=== stop-heroic-game.sh finished ==="
