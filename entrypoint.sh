#!/bin/bash

# this script is run by the docker container containing Claude Code
# at startup.

# make script fail on otherwise masked errors
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: entrypoint.sh <directory> [command] [args...]"
    echo "  directory: path to cd to before running the command"
    echo "  command:   command to run (default: claude)"
    echo "  args:      arguments passed to the command"
    exit 1
fi

WORK_DIR="$1"
shift

# Read the command to run. If the first argument names an executable in the
# container (bash, python3, ...), run that. 
# Otherwise treat everything as arguments for Claude Code, so that both flags --resume and `mcp list` keep working.
if [ $# -ge 1 ] && command -v "$1" >/dev/null 2>&1; then
    CMD="$1"
    shift
else
    CMD="claude"
fi

cd "/workdir/$WORK_DIR"

export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
# only when using API authentication
#export ANTHROPIC_BASE_URL=https://your-proxy.example.com/
#export ANTHROPIC_AUTH_TOKEN=your-token

export HOME=/tmp/home

exec "$CMD" "$@"
