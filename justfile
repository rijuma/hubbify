set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    @just --list

# Create the external network the proxy and all projects attach to
_network:
    @docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

# Build and start the reverse proxy locally
up: _network
    docker compose -f proxy/compose.yml up -d --build

# Stop the reverse proxy
down:
    docker compose -f proxy/compose.yml down

# Follow proxy logs
logs:
    docker compose -f proxy/compose.yml logs -f caddy

# Trust Caddy's local CA so browsers accept https://*.localhost (WSL + Windows)
trust:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    docker compose -f proxy/compose.yml cp caddy:/data/caddy/pki/authorities/local/root.crt "$tmp/hubbify-local-ca.crt"
    sudo cp "$tmp/hubbify-local-ca.crt" /usr/local/share/ca-certificates/hubbify-local-ca.crt
    sudo update-ca-certificates
    if command -v certutil.exe >/dev/null 2>&1; then
        certutil.exe -addstore -user Root "$(wslpath -w "$tmp/hubbify-local-ca.crt")"
    else
        echo "certutil.exe not found — skipping Windows cert store (Linux store updated)."
    fi
    rm -rf "$tmp"

# Open a shell on a server (or run a command, e.g. `just ssh myvps df -h`)
ssh server *cmd="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n {{quote(cmd)}} ]; then
        exec ssh -t {{server}} {{quote(cmd)}}
    else
        exec ssh {{server}}
    fi

# Free disk on a server: prune docker leftovers, old packages and logs
cleanup server:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== Disk before =="
    ssh {{server}} "df -h /"
    ssh {{server}} "docker system prune -f"
    ssh {{server}} "sudo apt-get -yq autoremove --purge && sudo apt-get clean && sudo journalctl --vacuum-time=30d"
    echo "== Disk after =="
    ssh {{server}} "df -h /"

# Update a server: install OS updates, then rebuild + redeploy the proxy
upgrade server:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh {{server}} "sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get -yq upgrade"
    just remote-up {{server}}
    if ssh {{server}} "test -f /var/run/reboot-required"; then
        echo "Reboot required — run: just ssh {{server}} sudo reboot"
    else
        echo "No reboot required."
    fi

# Create a server folder from the template, e.g. `just server-create myvps`
server-create name:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{justfile_directory()}}/servers/{{name}}"
    [ ! -e "$dir" ] || { echo "servers/{{name}} already exists"; exit 1; }
    cp -r "{{justfile_directory()}}/servers/_template" "$dir"
    echo "Created servers/{{name}} — fill in server.env"

# Remove a server folder, e.g. `just server-remove myvps`
[confirm("This deletes the server's secrets and project envs. Continue? (y/N)")]
server-remove name:
    #!/usr/bin/env bash
    set -euo pipefail
    [ "{{name}}" != "_template" ] || { echo "Refusing to remove the template"; exit 1; }
    rm -rf "{{justfile_directory()}}/servers/{{name}}"

# Build and start the proxy on a server, e.g. `just remote-up myvps`
remote-up context:
    docker --context {{context}} network inspect proxy >/dev/null 2>&1 || docker --context {{context}} network create proxy
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml up -d --build

# Follow proxy logs on a server
remote-logs context:
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml logs -f caddy
