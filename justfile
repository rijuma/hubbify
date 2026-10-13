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

# Update a server: install OS updates, then rebuild + redeploy the proxy and refresh its firewall
upgrade server:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh {{server}} "sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get -yq upgrade"
    just remote-up {{server}}
    just firewall {{server}}
    if ssh {{server}} "test -f /var/run/reboot-required"; then
        echo "Reboot required — run: just ssh {{server}} sudo reboot"
    else
        echo "No reboot required."
    fi

# Restrict 80/443 to Cloudflare when server.env has CLOUDFLARE_ONLY=true, else lift it
firewall server:
    #!/usr/bin/env bash
    set -euo pipefail
    cloudflare_only=$(sed -n 's/^CLOUDFLARE_ONLY=//p' servers/{{server}}/server.env | tail -n 1)
    case "$cloudflare_only" in
        ''|true) ;;
        *) echo "CLOUDFLARE_ONLY must be empty or true (got '$cloudflare_only')" >&2; exit 1 ;;
    esac
    strip_block='/^# BEGIN hubbify$/,/^# END hubbify$/d'
    # Runs on the server before every strip_block: a BEGIN without its END would make the
    # sed range delete to the end of the rules file $f.
    check_block='begins=$(sudo grep -c "^# BEGIN hubbify$" $f || true)
        ends=$(sudo grep -c "^# END hubbify$" $f || true)
        if [ "$begins" != "$ends" ] || [ "$begins" -gt 1 ]; then
            echo "$f has an unterminated or repeated hubbify block; fix it by hand" >&2; exit 1
        fi'

    # ufw reload leaves an undeclared chain alone, so the live DOCKER-USER rules are
    # flushed too (while opted in, every reload already resets that chain to the block).
    if [ "$cloudflare_only" != "true" ]; then
        removed=$(ssh {{server}} "set -e; for rules in after.rules:iptables after6.rules:ip6tables; do
            f=/etc/ufw/\${rules%:*}
            if sudo grep -qs '^# BEGIN hubbify\$' \$f; then
                $check_block
                sudo sed -i '$strip_block' \$f; sudo \${rules#*:} -F DOCKER-USER; echo \$f
            fi
        done")
        if [ -n "$removed" ]; then
            ssh {{server}} "sudo ufw reload"
        fi
        exit 0
    fi

    fetch_ranges() {
        local ranges
        ranges=$(curl -fsS "https://www.cloudflare.com/$1")
        if [ -z "$ranges" ] || grep -qvE '^[0-9a-f.:]+/[0-9]+$' <<<"$ranges"; then
            echo "Unexpected Cloudflare $1 list" >&2
            return 1
        fi
        echo "$ranges"
    }

    # --ctorigdstport matches the port before DNAT rewrote it; only DNATed (published-port)
    # traffic is dropped, so the containers' own outbound connections keep working.
    rules_block() {
        echo '# BEGIN hubbify'
        echo '*filter'
        echo ':DOCKER-USER - [0:0]'
        echo '-A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN'
        for cidr in $1; do
            for proto_port in tcp:80 tcp:443 udp:443; do
                echo "-A DOCKER-USER -s $cidr -p ${proto_port%:*} -m conntrack --ctorigdstport ${proto_port#*:} -j RETURN"
            done
        done
        for proto_port in tcp:80 tcp:443 udp:443; do
            echo "-A DOCKER-USER -p ${proto_port%:*} -m conntrack --ctstate DNAT --ctorigdstport ${proto_port#*:} -j DROP"
        done
        echo 'COMMIT'
        echo '# END hubbify'
    }

    write_block() {
        ssh {{server}} "f=$1; $check_block
            sudo sed -i '$strip_block' $1 && sudo tee -a $1 >/dev/null" <<<"$2"
    }

    ipv4_ranges=$(fetch_ranges ips-v4)
    ipv6_ranges=$(fetch_ranges ips-v6)
    ssh {{server}} "sudo ufw status | grep -q '^Status: active'" \
        || { echo "ufw is not active on {{server}}; enable it first" >&2; exit 1; }
    write_block /etc/ufw/after.rules "$(rules_block "$ipv4_ranges")"
    write_block /etc/ufw/after6.rules "$(rules_block "$ipv6_ranges")"
    ssh {{server}} "sudo ufw reload"

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
    mkdir -p servers/{{context}}/caddy
    docker --context {{context}} network inspect proxy >/dev/null 2>&1 || docker --context {{context}} network create proxy
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml up -d --build

# Follow proxy logs on a server
remote-logs context:
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml logs -f caddy
