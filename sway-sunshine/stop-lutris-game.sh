#!/bin/bash
# Stops a Lutris game launched via start-lutris-game.sh
# Usage: stop-lutris-game.sh [lutris_game_id]
#   Without arguments: stops ANY Lutris game process in the headless session
#   With game ID: stops only the process matching that specific game's rungameid URI

GAME_ID="$1"

# Build the pgrep pattern based on whether a game ID was provided
if [ -z "$GAME_ID" ]; then
    # No argument: match ANY Lutris game process (rungameid/ without specific ID)
    PATTERN="lutris:rungameid/"
else
    # Game ID provided: match only this specific game
    PATTERN="lutris:rungameid/$GAME_ID"
fi

# Find and kill the game process(es)
# Lutris launches the game with the rungameid URI in its process args
MATCHED_PIDS=$(pgrep -f "$PATTERN" 2>/dev/null || true)

if [ -z "$MATCHED_PIDS" ]; then
    exit 0
fi

# Send SIGTERM to matched processes
for PID in $MATCHED_PIDS; do
    kill "$PID" 2>/dev/null
done

# Wait for graceful shutdown
for i in $(seq 1 15); do
    ALL_EXITED=true
    for PID in $MATCHED_PIDS; do
        if kill -0 "$PID" 2>/dev/null; then
            ALL_EXITED=false
            break
        fi
    done
    $ALL_EXITED && break
    sleep 1
done

# Force kill any remaining processes
for PID in $MATCHED_PIDS; do
    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null
    fi
done

sleep 1

# Final cleanup: kill any remaining processes matching the pattern
pkill -f "$PATTERN" 2>/dev/null
