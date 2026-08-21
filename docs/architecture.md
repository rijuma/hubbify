# Architecture

Hubbify is a toolkit to set up and maintain VPS servers that host
docker-compose projects behind a single reverse proxy. The same setup runs
locally (for development) and remotely (on the server), so there is exactly one
config language and no generation step.

## The big picture

```
┌─ VPS (or local machine) ─────────────────────────────────┐
│                                                          │
│  caddy-docker-proxy ──── watches ───→ docker socket      │
│      │ :80/:443                                          │
│      │                                                   │
│  ════╪═══════════ external network: proxy ═══════════    │
│      │                    │                    │         │
│  ┌─ project A ─────┐  ┌─ project B ─────┐  ┌─ ... ─┐     │
│  │ web ←──────────────→ web             │  │       │     │
│  │  │ default net  │  │  │ default net  │  │       │     │
│  │ db (not on      │  │ redis           │  │       │     │
│  │     proxy net)  │  │                 │  │       │     │
│  └─────────────────┘  └─────────────────┘  └───────┘     │
└──────────────────────────────────────────────────────────┘
```

## Reverse proxy

The proxy is [lucaslorentz/caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy):
Caddy custom-built (see `proxy/Dockerfile`) with two modules:

- **caddy-docker-proxy** — watches the docker socket, builds a Caddyfile in
  memory from container labels, and hot-reloads Caddy when containers change.
- **caddy-dns/cloudflare** — solves ACME DNS-01 challenges against Cloudflare
  (remote only).

Projects declare their routing with exactly two labels (see
[project-contract.md](project-contract.md)); nothing else is allowed in labels.
Anything more complex goes into the base Caddyfile that caddy-docker-proxy
merges with the generated config:

- `proxy/Caddyfile` — local base (empty; escape hatch only).
- `proxy/Caddyfile.remote` — remote base (ACME email + `acme_dns cloudflare`).

## TLS

- **Locally** every project uses a `<name>.localhost` domain. Caddy serves
  these with its internal CA, so dev traffic is real HTTPS.
- **Remotely** all certificates are issued via DNS-01 through Cloudflare
  (`CLOUDFLARE_API_TOKEN` from `servers/<name>/server.env`, injected into the
  proxy container at deploy). This works behind Cloudflare's proxy (orange
  cloud) and needs no port-80 challenge.
- **Cloudflare zones must use SSL/TLS mode "Full (strict)".** Caddy holds
  real certificates, and it redirects port 80 to HTTPS — under "Flexible"
  Cloudflare fetches the origin over plain HTTP, which loops on that
  redirect (endless 308s).

## Isolation

Each project keeps its own compose default network for internal traffic
(app ↔ db, etc.). Only the web-facing service additionally joins the external
`proxy` network. Projects cannot see each other, and databases are never
reachable from the proxy network. No project publishes ports; only the proxy
binds 80/443.

## Servers

One hubbify checkout manages any number of servers. A server is identified by
one name used everywhere: the SSH alias in `~/.ssh/config`, the docker
context, and its folder in this repo:

```
servers/<name>/
  server.env            server-level secrets: CLOUDFLARE_API_TOKEN (gitignored)
```

Server folders are created with `just server-create <name>`, which copies
`servers/_template/` (the only tracked entry under `servers/`; everything else
is gitignored local state), and deleted with `just server-remove <name>` after
confirmation.

A server folder exists only to install and update hubbify itself (the proxy
stack) on that server. Nothing project-related lives here: each project's
production config belongs to the project's own repo, as GitHub environment
secrets used by its deploy workflow.

Day-to-day host maintenance is also a recipe away, always run from the
client over SSH (the server name doubles as the SSH alias): `just ssh` for a
shell, `just cleanup` to reclaim disk (docker prune, apt autoremove/clean,
journal vacuum), `just upgrade` to install OS updates and rebuild + redeploy
the proxy, reporting whether a reboot is pending. These assume the admin user
the bootstrap creates (passwordless sudo).

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
- **Secrets never rest on the server's disk.** Production env reaches the
  server only as container environment — no plaintext `.env` files on the
  VPS or in its backups.
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

The manual escape hatch for a project without CI is running the same
`just deploy <env>` from the project directory with a local
`envs/<env>/.env`; hubbify does not manage project config.

## DNS (planned)

Cloudflare A records are upserted synchronously at deploy time, read from the
same `caddy` labels the proxy uses. The API token lives on the client/CI only,
never on the server. Explicit `dns prune` / `dns audit` commands handle
cleanup; there is no background watcher (async failures are invisible and
deletes are unsafe).

## Server bootstrap (planned)

An idempotent script prepares a fresh VPS: SSH hardening, ufw (ssh/80/443),
docker install, the `proxy` network, and the proxy stack. Until it exists, the
proxy can be started on any docker host with the `just` recipes.

## Repository layout

```
justfile              task entry points (just --list)
proxy/                the reverse proxy stack (local + remote overlay)
servers/<name>/       per-server secrets (server.env)
servers/_template/    tracked skeleton copied by `just server-create`
docs/                 you are here
```
