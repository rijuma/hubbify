# Architecture

Hubbify is a toolkit to set up and maintain VPS servers that host
docker-compose projects behind a single reverse proxy. The same setup runs
locally (for development) and remotely (on the server), so there is exactly one
config language and no generation step.

## The big picture

```mermaid
flowchart TB
    visitor["Visitor"]
    cf["Cloudflare<br/>(remote only)"]

    subgraph host["VPS or local machine"]
        sock[("docker socket")]
        caddy["caddy-docker-proxy<br/>only container binding 80/443"]

        subgraph proxynet["external network: proxy"]
            caddy
            webA["project A: web"]
            webB["project B: web"]
        end

        subgraph netA["project A default network"]
            dbA[("db")]
        end
        subgraph netB["project B default network"]
            redisB[("redis")]
        end

        subgraph apinet["internal network: docker-api"]
            socketproxy["socket-proxy<br/>read-only Docker API"]
        end

        caddy -->|"reverse_proxy"| webA
        caddy -->|"reverse_proxy"| webB
        webA --- dbA
        webB --- redisB
    end

    visitor --> cf
    cf -->|"80/443"| caddy
    caddy -. "watches labels (GET only)" .-> socketproxy
    socketproxy -. "mounted read-only" .-> sock
```

## Reverse proxy

The proxy is [lucaslorentz/caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy):
Caddy custom-built (see `proxy/Dockerfile`) with three modules:

- **caddy-docker-proxy** — watches the Docker API through the socket proxy,
  builds a Caddyfile in memory from container labels, and hot-reloads Caddy
  when containers change.
- **caddy-dns/cloudflare** — solves ACME DNS-01 challenges against Cloudflare
  (remote only).
- **caddy-cloudflare-ip** — provides Cloudflare's IP ranges, refreshed by the
  module, as a `trusted_proxies` source (remote only).

Projects declare their routing with exactly two labels (see
[project-contract.md](project-contract.md)), plus up to three flat extras to
guard an environment (`caddy.basic_auth.<user>`, `caddy.header.<Name>`,
`caddy.respond`); nothing else is allowed in labels. Anything more complex
goes into the base Caddyfile that caddy-docker-proxy merges with the
generated config:

- `proxy/Caddyfile` — local base (empty; escape hatch only).
- `servers/local/caddy/Caddyfile` — optional extras for the local proxy, the
  local counterpart of a server's file below (e.g. the same headers on a
  project's `.localhost` domain).
- `proxy/Caddyfile.remote` — remote base (ACME email, `acme_dns cloudflare`,
  Cloudflare `trusted_proxies`).
- `servers/<name>/caddy/Caddyfile` — optional per-server extras (redirects
  and whatever else the allowed labels can't express for the sites that
  server hosts), as plain Caddyfile.

The base Caddyfiles are baked into the proxy image. The build takes one
`servers/<name>/caddy/` folder as an extra build context: `servers/local/caddy/`
on `just up` (from `proxy/compose.yml`), the server's own folder on
`just remote-up` (from `proxy/compose.remote.yml`). `proxy/Dockerfile` appends
its `Caddyfile`, when present, to the end of the base files; without one the
bases are used as they are. The blocks are appended inline rather than imported because caddy-docker-proxy
does not expand `import`, and a block for a label-generated domain is merged
with that site like any other base-Caddyfile block. That merge needs the block's address to be exactly the one domain: a
block listing several domains is a separate site that shadows the generated
ones, so each domain gets its own block.

```mermaid
flowchart LR
    base["proxy/Caddyfile or<br/>proxy/Caddyfile.remote"] --> build["docker build<br/>proxy/Dockerfile"]
    extras["servers/&lt;name&gt;/caddy/Caddyfile<br/>(optional; servers/local locally)"] -->|"appended inline"| build
    build --> image["proxy image<br/>base Caddyfile baked in"]
    labels["project labels<br/>caddy + caddy.reverse_proxy"] -->|"read through socket-proxy"| gen["generated config"]
    image --> merged["running Caddy config<br/>hot-reloaded on container changes"]
    gen --> merged
```

Caddy is the only container exposed to the internet, so it never holds the
Docker socket: a socket mounted `:ro` still accepts every API call, and a
label such as `caddy.reverse_proxy: unix//var/run/docker.sock` would hand the
daemon to anyone who can reach that site. Instead the `socket-proxy` service
([tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy),
pinned by digest in `proxy/compose.yml`) mounts the socket read-only and
answers only GET requests on the sections caddy-docker-proxy reads
(containers, networks, info, events, ping, version); every other request,
and every POST, gets a 403. It publishes no ports and joins only
`docker-api`, a network declared `internal: true` that only it and Caddy
join; Caddy reaches it through `DOCKER_HOST=tcp://socket-proxy:2375` and
keeps routing over `proxy` (`CADDY_INGRESS_NETWORKS=proxy`). The Caddy
container also drops every Linux capability except `NET_BIND_SERVICE` (to
bind 80/443) and runs with `no-new-privileges`. The pinned
`socket-proxy` image, the `caddy` base images and plugin versions in
`proxy/Dockerfile` and the SHA-pinned workflow actions are bumped by hand.

## TLS

- **Locally** every project uses a `<name>.localhost` domain. Caddy serves
  these with its internal CA, so dev traffic is real HTTPS. `just trust`
  installs that CA in the WSL/Linux store and, when available, the Windows
  user store, so browsers accept it.
- **Remotely** all certificates are issued via DNS-01 through Cloudflare
  (`CLOUDFLARE_API_TOKEN` from `servers/<name>/server.env`, injected into the
  proxy container at deploy). This works behind Cloudflare's proxy (orange
  cloud) and needs no port-80 challenge. Each server gets its own token,
  scoped to Zone → DNS → Edit on only the zones that server hosts, never one
  token shared across servers: every deployer on a server can read it (see
  [the trust model](project-contract.md#trust-model)).
- **Cloudflare zones must use SSL/TLS mode "Full (strict)".** Caddy holds
  real certificates, and it redirects port 80 to HTTPS — under "Flexible"
  Cloudflare fetches the origin over plain HTTP, which loops on that
  redirect (endless 308s).
- **Caddy sees the visitor, not Cloudflare.** `proxy/Caddyfile.remote` sets
  `trusted_proxies cloudflare` and `client_ip_headers CF-Connecting-IP`, so
  `{client_ip}` and access logs show the visitor for requests that arrive
  from Cloudflare's ranges; requests from any other peer keep the peer's
  address. This holds on every remote server.
- **Cloudflare-only origin (opt-in).** On servers with `CLOUDFLARE_ONLY=true`,
  `just firewall` drops inbound 80/443 (TCP, and UDP 443 for HTTP/3) from
  anything outside Cloudflare's ranges. The origin IP is closed to everyone
  but Cloudflare once `just firewall` has completed with the flag set, which
  on a host with a global IPv6 address needs a `proxy` network with IPv6 (see
  Firewall). Closing 80 does not break renewal: DNS-01 needs no
  inbound challenge traffic. Servers that also host grey-cloud (DNS only)
  domains leave the flag empty and keep 80/443 open.

## Isolation

Each project keeps its own compose default network for internal traffic
(app ↔ db, etc.). Only the web-facing service additionally joins the external
`proxy` network. A project's default network (databases, workers) is not
reachable from other projects or from the proxy network. Web-facing services
all share `proxy`, so they can reach each other there; a service on `proxy`
reaches its own siblings only by project-unique names (rule 6 in
[project-contract.md](project-contract.md)). No project publishes ports; only
the proxy binds 80/443. Traffic between services on `proxy` bypasses Caddy,
so a proxy-level guard such as `caddy.basic_auth` does not protect a service
from its neighbours, and a neighbour can send any `CF-Connecting-IP` value.
The network isolates projects from the internet, not from each other; see
[the trust model](project-contract.md#trust-model).

## Servers

One hubbify checkout manages any number of servers. A server is identified by
one name used everywhere: the SSH alias in `~/.ssh/config`, the docker
context, and its folder in this repo. The name uses only lowercase letters,
digits and hyphens, starts with a letter or digit, and is not `local`, which is
reserved for the local proxy; the recipes that turn it into a path under
`servers/` reject any other name:

```
servers/<name>/
  server.env            server secrets and settings: CLOUDFLARE_API_TOKEN,
                        ACME_EMAIL, SERVER_NAME, CLOUDFLARE_ONLY (gitignored)
  caddy/Caddyfile       optional per-server Caddyfile (gitignored)
  source                optional: where the shared copy of the two files above
                        lives, as op://<vault> (gitignored)
```

The `caddy/` subfolder holds only the Caddyfile because the docker build
uploads a whole build-context folder to the server's daemon, so pointing it at
`servers/<name>/` would ship `server.env` to the server and keep it in the
build cache. `CLOUDFLARE_API_TOKEN` in `server.env` is that server's own
token, limited to the zones it hosts (see TLS). `remote-up` creates the
folder if it is missing, and `up` does the same for `servers/local/caddy/`,
so `local` is a reserved name and the server recipes reject it. `SERVER_NAME` in
`server.env` must equal the `servers/<name>/` folder name: `remote-up` picks
the env file by the context (folder) name, while the build context path comes
from `SERVER_NAME`.

Server folders are created with `just server-create <name>`, which copies
`servers/_template/` (the only tracked entry under `servers/`; everything else
is gitignored local state), and deleted with `just server-remove <name>` after
confirmation.

### Shared server config

A server folder is local state, so by default it exists on one person's
machine. When several people administer the same server, the folder can keep
its shared copy in a 1Password vault they all read. The folder's `source` file
names that vault as `op://<vault>`, and the vault holds one document per file,
titled `<name> server.env` and `<name> Caddyfile`.

| Task                                    | Command                                  |
| --------------------------------------- | ---------------------------------------- |
| Publish a server folder the first time  | `just server-push <name> op://<vault>`   |
| Set the server up on another machine    | `just server-create <name> op://<vault>` |
| Publish a local change                  | `just server-push <name>`                |
| Take the shared copy, overwriting local | `just server-pull <name>`                |

- **The vault is the source of truth.** `remote-up`, `remote-logs`, `firewall`
  and `upgrade` compare the local files with the shared copy first and stop
  when they differ, naming the files and the two commands above. A stale
  folder and an unpublished local edit look the same to that check, so it
  never picks a side on its own.
- **Editing.** Change the local file, `just server-push <name>`, then run the
  recipe. Deleting the local Caddyfile and pushing removes its document.
- **Sign-in.** These recipes need the 1Password CLI (`op`) signed in
  (`eval $(op signin)`); they stop with that hint otherwise. A session lasts
  until its terminal closes or sits idle for about 30 minutes. A server folder
  without a `source` file never calls `op`. To sign in only when the session
  has expired, add this to `~/.bashrc` and run `hub <recipe>` in place of
  `just <recipe>`:

  ```bash
  hub() {
    op whoami >/dev/null 2>&1 || eval "$(op signin)"
    just "$@"
  }
  ```

- **What the vault gives and what it does not.** Everyone who can read the
  vault can read the server's Cloudflare token, which is the point. 1Password
  keeps earlier versions of a document but offers no review or diff, and the
  last push wins.
- `op://` is the only source kind there is. `scripts/server-config.sh` does
  the work, and `scripts/server-config.test.sh` checks it against a stand-in
  for `op`.

A server folder exists only to install and update hubbify itself (the proxy
stack) on that server. Beyond the proxy-side site extras in
`caddy/Caddyfile`, nothing project-related lives here: each project's
production config belongs to the project's own repo, as GitHub environment
secrets used by its deploy workflow.

Day-to-day host maintenance is also a recipe away, always run from the
client over SSH (the server name doubles as the SSH alias): `just ssh` for a
shell, `just cleanup` to reclaim disk (docker prune, apt autoremove/clean,
journal vacuum), `just upgrade` to install OS updates, rebuild + redeploy
the proxy, report whether a reboot is pending and then refresh the firewall;
it fails if `just firewall` refuses, after the reboot report. These assume
the admin user the bootstrap creates (passwordless sudo).

## Deploys

All deploys run over an SSH docker context
(`docker --context <server> compose up -d --build`): the docker CLI and
compose run on the client, read the compose files there, and stream the
result to the server's daemon. No agent, no git checkout, nothing
hubbify-specific runs on the server beyond docker and the proxy stack.

Why the server holds no compose files:

- **Git is the single source of truth.** With nothing on the server to edit,
  the running state always corresponds to a commit; there is no second copy
  to drift out of sync after a 2am hotfix.
- **No sync machinery, no server credentials.** The server never clones
  repos, so it needs no deploy keys to anything; auth flows one way, from
  client to server, and "sync + apply" is one command.
- **No `.env` files on the server.** Production env reaches the server only
  as container environment, never as a `.env` file on the VPS or in a
  checkout there. Docker still stores that environment in the container's
  config on the server's disk, and `docker inspect` shows it to anyone with
  Docker access.
- **Servers are disposable.** A VPS carries only runtime state (volumes);
  everything else is re-creatable by replaying deploys. There is also no
  hubbify footprint on the server to keep updated.
- **CI-shaped by construction.** A GitHub Actions runner does exactly what a
  laptop does — same command, same SSH context — with no server-side hooks.

The tradeoffs, accepted knowingly: deploying requires a machine with the
repo, a docker client, and SSH access; and `--build` ships the build context
over SSH on every deploy (the GHCR path removes both — CI builds, the server
pulls).

The server is still fully inspectable by hand: compose v2 reconstructs
projects from container labels, so over `just ssh` the usual
`docker compose ls` and `docker compose -p <project> ps|logs|restart|stop`
work with no files present. The only thing the box cannot do is change a
definition (`up` from files) — definition changes go through git.

Hubbify only deploys the proxy: `just remote-up <server>`. Projects deploy
from their own repos — the canonical path is the manual-dispatch GitHub
workflow shipped by hubbify-template, with one GitHub environment per env
folder (`envs/<env>/`): an SSH deploy key + pinned host key create the
docker context the env's `server.conf` declares, and the environment's
`ENV_FILE` secret is written to `envs/<env>/.env` on the runner —
production secrets live in GitHub, never on a laptop or in hubbify. Before
`up`, the deploy checks the server's `hubbify.server` stamp against the
env's `SERVER_NAME` (see the project contract), so a context pointing at
the wrong machine aborts. The upgrade path for bigger projects is GitHub
Actions building images to GHCR, with the same compose-over-context deploy
pulling instead of building.

```mermaid
sequenceDiagram
    participant H as hubbify checkout
    participant P as project repo / CI runner
    participant D as server docker daemon
    participant C as caddy-docker-proxy

    Note over H,D: once per server, and on every upgrade
    H->>D: just remote-up name (Docker 27+ check, proxy network with IPv6)
    H->>D: compose up --build, server.env as container env
    D->>C: start proxy stamped hubbify.server=SERVER_NAME

    Note over P,D: every project deploy
    P->>P: write envs/env/.env from the ENV_FILE secret
    P->>D: is a container stamped with the env's SERVER_NAME running?
    D-->>P: yes, else the deploy aborts
    P->>D: compose up -d --build (base + env overlay)
    D-->>C: container started with caddy labels
    C->>C: regenerate config, get certificate via DNS-01
```

The manual escape hatch for a project without CI is running the same
`just deploy <env>` from the project directory with a local
`envs/<env>/.env`; hubbify holds no project env or deploy config, only the
proxy-side site extras that don't fit the allowed labels, in
`servers/<name>/caddy/Caddyfile`.

## Firewall

`just firewall <name>` applies `CLOUDFLARE_ONLY` from `server.env` (empty or
missing means off; any value other than `true` aborts). When `true`, it
fetches Cloudflare's IPv4 and IPv6 lists on the client, aborts if ufw is not
active on the server or if the server has a global IPv6 address that Docker
does not route through `DOCKER-USER` (see below), writes a `# BEGIN hubbify`
… `# END hubbify` block into `/etc/ufw/after.rules` and
`/etc/ufw/after6.rules` (replacing the previous one) and reloads ufw. When
off, it removes that block, flushes the live `DOCKER-USER` chain (a ufw
reload alone would leave the rules until reboot) and reloads ufw, doing
nothing if there was no block, so opting out is clearing the flag and
rerunning. It touches no other rule, so SSH stays as configured, and it
refuses to edit a rules file whose hubbify block is unterminated or repeated.
Running it again yields the same files; `upgrade` calls it so Cloudflare's
ranges stay current.

ufw must be active before `just firewall` runs on a `CLOUDFLARE_ONLY` server.
ufw's own allow/deny rules do not cover the proxy's 80/443: Docker DNATs
published-port traffic to the container in its own iptables rules, so it is
forwarded past ufw's `INPUT` rules. The hubbify block therefore filters in
Docker's `DOCKER-USER` chain, fed from ufw's `after.rules` and `after6.rules`,
which ufw loads at boot. The block declares `DOCKER-USER` itself, because ufw
starts before Docker creates the chain, and so each ufw reload resets the
chain instead of appending duplicates. It returns established/related traffic
first, then traffic from Cloudflare's ranges, and drops only DNATed
(published-port) connections whose original destination port is 80 or 443, so
the containers' own outbound traffic keeps working.

```mermaid
flowchart TD
    pkt["forwarded packet<br/>in DOCKER-USER"] --> est{"established<br/>or related?"}
    est -->|"yes"| ret["RETURN: Docker's rules continue"]
    est -->|"no"| cfr{"source in Cloudflare ranges<br/>and original port 80/443?"}
    cfr -->|"yes"| ret
    cfr -->|"no"| dnat{"DNATed to a published<br/>port 80 or 443?"}
    dnat -->|"yes"| drop["DROP"]
    dnat -->|"no: e.g. container outbound"| ret
```

The IPv6 block only sees IPv6 traffic when Docker routes it through
`DOCKER-USER`, which needs both Docker's ip6tables support (on by default) and
a `proxy` network created with `--ipv6`. Otherwise Docker's userland
docker-proxy carries published IPv6 traffic, which then passes ufw's `INPUT`
(where 80/443 are allowed) and never reaches `DOCKER-USER`. So on a
`CLOUDFLARE_ONLY` server with a global IPv6 address (ULA `fd00::/8` addresses
do not count), `just firewall` checks both and aborts unless they hold.

hubbify requires Docker 27 or later on servers: `just remote-up` aborts on an
older daemon. It creates the `proxy` network with `--ipv6` when it does not
exist, with the IPv6 subnet picked from the daemon's default pool. An existing
`proxy` network is left as is, so fresh servers pass the check, while a server
whose network was created without IPv6 needs it recreated:

1. Take the proxy (project `proxy`) and every project down with
   `docker --context <name> compose -p <project> down`, which removes their
   containers; `docker network rm proxy` fails while any is attached.
2. `docker --context <name> network rm proxy`
3. `just remote-up <name>`, which creates the network with IPv6.
4. Redeploy the projects.
5. `just firewall <name>`

## DNS (planned)

Cloudflare A records are upserted synchronously at deploy time, read from the
same `caddy` labels the proxy uses. The upserts run from the client/CI with
the server's token from `servers/<name>/server.env` and put no further copy
on the server; that token already sits in the proxy container's env for
DNS-01 (see [TLS](#tls)). Explicit `dns prune` / `dns audit` commands handle
cleanup; there is no background watcher (async failures are invisible and
deletes are unsafe).

## Server bootstrap (planned)

An idempotent script prepares a fresh VPS: SSH hardening, ufw (ssh/80/443),
Docker 27+ install, and the proxy stack. Until it exists, the
proxy can be started on any docker host with the `just` recipes.

`just firewall`, which builds on that ufw setup, already exists; see Firewall.

## Repository layout

```
justfile              task entry points (just --list)
proxy/                the reverse proxy stack (local + remote overlay)
servers/<name>/       per-server secrets (server.env), caddy/Caddyfile and an
                      optional source pointing at their shared copy
scripts/              helper scripts the recipes call
servers/local/        caddy/Caddyfile for the local proxy (no server.env)
servers/_template/    tracked skeleton copied by `just server-create`
docs/                 you are here
```
