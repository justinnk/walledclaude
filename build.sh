#!/bin/bash
set -euo pipefail

# Convenience script to build the walledclaude Docker image.

# Ask the npm registry for the current version. Set WALLEDCLAUDE_VERSION to pin a specific version.
CLAUDE_VERSION="${WALLEDCLAUDE_VERSION:-$(curl -fsSL \
    https://registry.npmjs.org/-/package/@anthropic-ai%2fclaude-code/dist-tags \
    | sed -n 's/.*"latest":"\([^"]*\)".*/\1/p')}"

if [ -z "$CLAUDE_VERSION" ]; then
    echo "build.sh: could not determine the most recent Claude Code version." >&2
    echo "  Check your connection, or set WALLEDCLAUDE_VERSION explicitly." >&2
    exit 1
fi

IMAGE="claude-code"

# tag with the version so we can go back to older ones when breaking changes
# occur, and with `latest` so walledclaude.sh has a stable default to launch.
docker buildx build --network=host --build-arg CLAUDE_VERSION="$CLAUDE_VERSION" \
    -t "$IMAGE:$CLAUDE_VERSION" -t "$IMAGE:latest" .

echo "built $IMAGE:$CLAUDE_VERSION (also tagged $IMAGE:latest)"
