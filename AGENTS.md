# AGENTS.md — Build Orchestrator Rules

## Deployment Discipline

**NEVER update live services and config files directly.**

All changes must be made to the source files in this repository first, then deployed to the live system using `install.sh`.

This means:
- Source files live in: `systemd/`, `sway-sunshine/`, `sunshine/`, `pipewire/`, `udev/`
- Live config paths are: `~/.config/systemd/user/`, `~/.config/sway-sunshine/`, `~/.config/sunshine/`, `~/.config/pipewire/`
- Always edit the repo files, then run `./install.sh` to copy them to the live system
- This ensures config changes are tracked in git and can be reproduced
