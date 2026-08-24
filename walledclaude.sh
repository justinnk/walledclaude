# this function will launch a dockerized version of Claude Code including
# a proxy to control network traffic.
#
# Source this file from your shell config (bash or zsh) using its full path:
#   source ~/path/to/walledclaude/walledclaude.sh
#
# Optional environment variables:
#   WALLEDCLAUDE_VERSION  Claude Code version/image tag to run (default: latest)
#   WALLEDCLAUDE_CPUS     CPU limit for the container (default: all host cores - 1)
#   WALLEDCLAUDE_MEMORY   memory limit for the container (default: 4g)
#
# set them with `export NAME=value` in your shell config.

# Resolve the directory of this file in zsh and bash.
if [ -n "${ZSH_VERSION:-}" ]; then
    eval 'WALLEDCLAUDE_DIR=${(%):-%x}'
else
    WALLEDCLAUDE_DIR="${BASH_SOURCE[0]}"
fi
WALLEDCLAUDE_DIR="$(cd "$(dirname "$WALLEDCLAUDE_DIR")" && pwd)"

walledclaude() {
    # for added coolness when launching ;)
    # comment out if it annoys you.
    set -o xtrace

    local SCRIPT_DIR
    SCRIPT_DIR="$WALLEDCLAUDE_DIR"
    if [ ! -f "$SCRIPT_DIR/squid.conf" ]; then
        echo "walledclaude: cannot find squid.conf in '$SCRIPT_DIR'." >&2
        set +o xtrace
        return 1
    fi

    # launch whatever build.sh last built or what is specified as WALLEDCLAUDE_VERSION 
    local IMAGE
    IMAGE="claude-code:${WALLEDCLAUDE_VERSION:-latest}"
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "walledclaude: image '$IMAGE' not found. Run ./build.sh first." >&2
        set +o xtrace
        return 1
    fi

    # the working directory in which walledclaude is launched as
    # well as the folder (project) name
    local cwd proj
    cwd=$(pwd -P)
    proj=$(basename "$cwd")

    # set up forward proxy to control egress. Only allow calls to *.anthropic.com
    local EGRESS_NET SANDBOX_NET PROXY_NAME SQUID_IMAGE
    EGRESS_NET="claude-egress"      # internet-facing; proxy only
    SANDBOX_NET="claude-sandbox"    # --internal (no route out); claude only
    PROXY_NAME="claude-egress-proxy"
    # pin squid version to avoid supply chain risks
    SQUID_IMAGE="ubuntu/squid@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029"

    # create dedicated networks if missing
    docker network inspect "$EGRESS_NET"  >/dev/null 2>&1 || docker network create "$EGRESS_NET" >/dev/null
    docker network inspect "$SANDBOX_NET" >/dev/null 2>&1 || docker network create --internal "$SANDBOX_NET" >/dev/null

    # recreate the proxy if it is missing or if squid.conf changed since it
    # started
    local conf_sum running_sum
    # macOS has no sha256sum, but ships shasum
    if command -v sha256sum >/dev/null 2>&1; then
        conf_sum=$(sha256sum "$SCRIPT_DIR/squid.conf" | cut -c1-16)
    else
        conf_sum=$(shasum -a 256 "$SCRIPT_DIR/squid.conf" | cut -c1-16)
    fi
    running_sum=$(docker inspect -f '{{index .Config.Labels "squid.conf.sum"}}' "$PROXY_NAME" 2>/dev/null || true)

    if [ "$running_sum" != "$conf_sum" ] || ! docker ps --format '{{.Names}}' | grep -qx "$PROXY_NAME"; then
        docker rm -f "$PROXY_NAME" >/dev/null 2>&1 || true
        # Proxy joins the internal net first...
        # same hardening as the Claude container: no privilege escalation, all capabilities
        # dropped except the few squid actually needs (SETUID/SETGID/KILL to
        # spawn and manage its unprivileged worker; CHOWN/FOWNER/DAC_OVERRIDE
        # to set up its log/cache dirs), plus resource caps
        docker run -d --name "$PROXY_NAME" \
            --network "$SANDBOX_NET" \
            --restart unless-stopped \
            --security-opt=no-new-privileges \
            --cap-drop=ALL \
            --cap-add=SETUID --cap-add=SETGID --cap-add=KILL \
            --cap-add=CHOWN --cap-add=FOWNER --cap-add=DAC_OVERRIDE \
            --pids-limit=256 --memory=512m \
            --label "squid.conf.sum=$conf_sum" \
            -v "$SCRIPT_DIR/squid.conf:/etc/squid/squid.conf:ro" \
            "$SQUID_IMAGE" #>/dev/null
        # ...then gets the ONLY path to the internet.
        docker network connect "$EGRESS_NET" "$PROXY_NAME"
        # if it fails to start, show log
        sleep 1
        if ! docker ps --format '{{.Names}}' | grep -qx "$PROXY_NAME"; then
            echo "walledclaude: egress proxy failed to start:" >&2
            docker logs "$PROXY_NAME" 2>&1 | tail -20 >&2
            set +o xtrace
            return 1
        fi
    fi

    # get current user uid/gid to give files created inside the container the
    # right metadata for convenience
    local host_uid host_gid
    host_uid=$(id -u)
    host_gid=$(id -g)

    # resource limits
    local cores cpus mem
    # nproc on Linux, sysctl on macOS
    cores=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 2)
    # leave one core for the host, but never ask docker for less than one
    cpus="${WALLEDCLAUDE_CPUS:-$(( cores > 1 ? cores - 1 : 1 ))}"
    mem="${WALLEDCLAUDE_MEMORY:-4g}"

    # make sure bind-mount sources exist as the right type, otherwise docker
    # creates them as root-owned directories.
    [ -e "$HOME/.walledclaude.json" ] || echo '{}' > "$HOME/.walledclaude.json"
    mkdir -p "$HOME/.walledclaude"

    # run claude code inside container and with proxy connection
    docker run -it --rm \
        --user "$host_uid:$host_gid" \
        --security-opt=no-new-privileges \
        --cap-drop=ALL \
        --pids-limit=512 --memory="$mem" --cpus="$cpus" \
        --network=$SANDBOX_NET \
        --add-host=host.docker.internal:host-gateway \
        -e TERM="$TERM" -e COLORTERM="$COLORTERM" \
        -e HTTPS_PROXY="http://$PROXY_NAME:3128" \
        -e HTTP_PROXY="http://$PROXY_NAME:3128" \
        -e NO_PROXY="localhost,127.0.0.1" \
        -v "$HOME/.walledclaude.json:/tmp/home/.claude.json" \
        -v "$HOME/.walledclaude:/tmp/home/.claude" \
        -v "$cwd:/workdir/$proj" \
        -w "/workdir/$proj" \
        "$IMAGE" \
        "$proj" "$@"

    set +o xtrace
}
