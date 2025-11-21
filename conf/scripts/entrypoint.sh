#!/bin/bash

# Set UTF-8 locale for emoji support
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Configure runtime proxy for npm/git if environment variables are set
if [ -n "$HTTP_PROXY" ]; then
    echo "Configuring runtime proxy..."
    npm config set proxy "$HTTP_PROXY"
    git config --global http.proxy "$HTTP_PROXY"
fi

if [ -n "$HTTPS_PROXY" ]; then
    npm config set https-proxy "$HTTPS_PROXY"
    git config --global https.proxy "$HTTPS_PROXY"
fi

# Display welcome message
echo "=========================================="
echo "  ttyd Web Terminal with tmux"
echo "=========================================="
echo "Terminal is ready!"
echo ""

# Configuration
TMUX_SESSION="main"
TTYD_PORT="${TTYD_PORT:-7681}"  # Default to 7681 if not set
TTYD_FONTSIZE="${TTYD_FONTSIZE:-16}"  # Default to 16 if not set

# Start ttyd with tmux
# -W: Allow clients to write to the terminal
# -t: Set terminal type with configurable font size
# -p: Port to listen on (configurable via TTYD_PORT environment variable)
# The command creates or attaches to a tmux session
exec ttyd -W -t "fontSize=${TTYD_FONTSIZE}" -p "${TTYD_PORT}" bash -c "tmux new-session -A -s ${TMUX_SESSION}"