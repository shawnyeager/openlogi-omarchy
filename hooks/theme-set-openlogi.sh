#!/bin/bash
# Omarchy theme-set hook — sync OpenLogi appearance with the active Omarchy theme.
# Installed via: omarchy hook install theme-set /path/to/this/file

set -euo pipefail

SYNC="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-openlogi/openlogi_sync.py"
exec python3 "${SYNC}" --theme-only --no-hook --no-agent
