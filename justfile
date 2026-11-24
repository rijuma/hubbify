set shell := ["bash", "-euo", "pipefail", "-c"]

_default:
    @just --list

# Create the external network the proxy and all projects attach to
_network:
    @docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

# Build and start the reverse proxy locally
up: _network
    mkdir -p servers/local/caddy
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
upgrade server: (_server-config server)
    #!/usr/bin/env bash
    set -euo pipefail
    ssh {{server}} "sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get -yq upgrade"
    just remote-up {{server}}
    if ssh {{server}} "test -f /var/run/reboot-required"; then
        echo "Reboot required — run: just ssh {{server}} sudo reboot"
    else
        echo "No reboot required."
    fi
    just firewall {{server}}

# Restrict published ports to Cloudflare on 80/443 (and ALLOW_INTERFACES) when server.env has CLOUDFLARE_ONLY=true, else lift it
firewall server: (_server-config server)
    #!/usr/bin/env bash
    set -euo pipefail
    cloudflare_only=$(sed -n 's/^CLOUDFLARE_ONLY=//p' servers/{{server}}/server.env | tail -n 1)
    case "$cloudflare_only" in
        ''|true) ;;
        *) echo "CLOUDFLARE_ONLY must be empty or true (got '$cloudflare_only')" >&2; exit 1 ;;
    esac
    allow_interfaces=$(sed -n 's/^ALLOW_INTERFACES=//p' servers/{{server}}/server.env | tail -n 1)
    [[ "$allow_interfaces" =~ ^([a-zA-Z0-9_.-]+(,[a-zA-Z0-9_.-]+)*)?$ ]] \
        || { echo "ALLOW_INTERFACES must be empty or a comma-separated list of interface names (got '$allow_interfaces')" >&2; exit 1; }
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

    # --ctorigdstport matches the port before DNAT rewrote it. Only DNATed (published-port)
    # traffic is dropped, so the containers' own outbound connections keep working. The drop
    # covers every published port, not just the proxy's: Docker forwards published ports past
    # ufw, so a stray `-p` on any container would otherwise be open to the internet.
    rules_block() {
        echo '# BEGIN hubbify'
        echo '*filter'
        echo ':DOCKER-USER - [0:0]'
        echo '-A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN'
        for interface in ${allow_interfaces//,/ }; do
            echo "-A DOCKER-USER -i $interface -j RETURN"
        done
        for cidr in $1; do
            for proto_port in tcp:80 tcp:443 udp:443; do
                echo "-A DOCKER-USER -s $cidr -p ${proto_port%:*} -m conntrack --ctorigdstport ${proto_port#*:} -j RETURN"
            done
        done
        echo '-A DOCKER-USER -m conntrack --ctstate DNAT -j DROP'
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
    # Without Docker's ip6tables support and an IPv6 proxy network, docker-proxy carries
    # published IPv6 traffic through ufw's INPUT, so the v6 block would never see it.
    # ULA (fd00::/8) addresses are not reachable from the internet and do not count.
    global_ipv6=$(ssh {{server}} "ip -6 -o addr show scope global" | awk '$4 !~ /^fd/ {print $4}')
    if [ -n "$global_ipv6" ]; then
        proxy_ipv6=$(ssh {{server}} "sudo ip6tables -t nat -nL DOCKER >/dev/null 2>&1 \
            && docker network inspect proxy --format '{{{{.EnableIPv6}}' 2>/dev/null || true")
        if [ "$proxy_ipv6" != "true" ]; then
            {
                echo "{{server}} has a global IPv6 address, but Docker does not route IPv6 through"
                echo "DOCKER-USER, so the Cloudflare-only rules would not filter IPv6. That needs Docker's"
                echo "ip6tables support (on by default) and a proxy network with IPv6. To recreate the network:"
                echo "  1. docker --context {{server}} compose -p <project> down, for the proxy (project"
                echo "     'proxy') and every project, so no container is attached to the network"
                echo "  2. docker --context {{server}} network rm proxy"
                echo "  3. just remote-up {{server}}, which creates the network with IPv6"
                echo "  4. redeploy the projects"
                echo "  5. just firewall {{server}}"
            } >&2
            exit 1
        fi
    fi
    write_block /etc/ufw/after.rules "$(rules_block "$ipv4_ranges")"
    write_block /etc/ufw/after6.rules "$(rules_block "$ipv6_ranges")"
    ssh {{server}} "sudo ufw reload"

# Reject a server name that is not a plain folder name under servers/, or is the reserved local
_server-name name:
    @[[ {{quote(name)}} =~ ^[a-z0-9][a-z0-9-]*$ ]] \
        || { printf 'Invalid server name %s: use lowercase letters, digits and hyphens, starting with a letter or digit\n' {{quote(name)}} >&2; exit 1; }
    @[[ {{quote(name)}} != local ]] \
        || { echo 'Server name local is reserved for the local proxy (servers/local/)' >&2; exit 1; }

# Stop when a server folder with a `source` file differs from its shared copy
_server-config name: (_server-name name)
    @scripts/server-config.sh check {{name}}

# Create a server folder from the template, or from a shared copy: `just server-create myvps op://<vault>`
server-create name source="": (_server-name name)
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{justfile_directory()}}/servers/{{name}}"
    [ ! -e "$dir" ] || { echo "servers/{{name}} already exists"; exit 1; }
    if [ -z {{quote(source)}} ]; then
        cp -r "{{justfile_directory()}}/servers/_template" "$dir"
        echo "Created servers/{{name}} — fill in server.env"
        exit 0
    fi
    mkdir -p "$dir/caddy"
    scripts/server-config.sh pull {{name}} {{quote(source)}} || { rm -rf "$dir"; exit 1; }
    echo {{quote(source)}} > "$dir/source"

# Replace a server folder's files with its shared copy
server-pull name: (_server-name name)
    @scripts/server-config.sh pull {{name}}

# Publish a server folder's files as its shared copy; give op://<vault> the first time
server-push name source="": (_server-name name)
    @scripts/server-config.sh push {{name}} {{quote(source)}}

# Remove a server folder, e.g. `just server-remove myvps`
[confirm("This deletes the server's secrets and Caddyfile. Continue? (y/N)")]
server-remove name: (_server-name name)
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{justfile_directory()}}/servers/{{name}}"

# Build and start the proxy on a server, e.g. `just remote-up myvps`
remote-up context: (_server-config context)
    version=$(docker --context {{context}} version --format '{{{{.Server.Version}}'); \
        [ "${version%%.*}" -ge 27 ] \
        || { echo "hubbify needs Docker 27+ on the server; {{context}} runs Docker $version" >&2; exit 1; }
    mkdir -p servers/{{context}}/caddy
    docker --context {{context}} network inspect proxy >/dev/null 2>&1 \
        || docker --context {{context}} network create --ipv6 proxy
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml up -d --build

# Follow proxy logs on a server
remote-logs context: (_server-config context)
    docker --context {{context}} compose --env-file servers/{{context}}/server.env -f proxy/compose.yml -f proxy/compose.remote.yml logs -f caddy
