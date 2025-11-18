#!/bin/bash

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

# Tmux session name
TMUX_SESSION="main"

# Start ttyd with tmux
# -W: Allow clients to write to the terminal
# -t: Set terminal type
# -p: Port to listen on
# The command creates or attaches to a tmux session
exec ttyd -W -t fontSize=16 -p 7681 bash -c "tmux new-session -A -s ${TMUX_SESSION}"