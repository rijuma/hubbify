# Project contract

What a docker-compose project must do to be hosted behind the hubbify proxy.
New projects should start from
[hubbify-template](https://github.com/rijuma/hubbify-template), which honors
this contract out of the box.

## The rules

1. **Join the proxy network** — only the web-facing service joins the external
   `proxy` network, in addition to the project's default network. Everything
   else (databases, workers) stays on the default network only.

2. **Declare exactly two labels** on the web-facing service, with the local
   `.localhost` domain in the base `compose.yml`:

   ```yaml
   labels:
     caddy: myapp.localhost
     caddy.reverse_proxy: "{{upstreams 3000}}"
   ```

   `caddy` is the domain; the number in `{{upstreams N}}` is the container
   port the app listens on. Each remote environment's overlay
   (`envs/<env>/compose.yml`) overrides only the domain label (compose merges
   labels by key):

   ```yaml
   labels:
     caddy: myapp.com
   ```

   A bare `docker compose up` therefore always serves `.localhost` — no env
   vars, no flags — while deploys always pass base + env overlay, so the real
   domain cannot be forgotten. The local domain must be the baseline: if the
   real domain were the default, a local run would attempt real ACME
   challenges.

3. **No other `caddy.*` labels.** If a project needs more than
   domain + port (extra headers, auth, redirects), that config goes into the
   hosting server's `servers/<name>/caddy/Caddyfile` in hubbify, written as
   plain Caddyfile — never as label trees. A block for the project's domain
   there is merged with the site its labels generate, and only that server
   serves it.

4. **Do not publish ports.** The proxy reaches the app over the `proxy`
   network; only the proxy binds 80/443 on the host.

5. **Deploy by environment, verify the server stamp.** A project's deploy
   targets live in `envs/<env>/` folders: a `server.conf` declaring
   `DOCKER_CONTEXT` (the docker SSH context) and `SERVER_NAME` marks the env
   as remote; a folder without one is local. Hubbify stamps every server's
   proxy with a `hubbify.server: <name>` label (from `SERVER_NAME` in
   `servers/<name>/server.env`), and project deploys must abort unless the
   context's stamp matches the env's `SERVER_NAME`. This makes
   deploying-to-the-wrong-server fail closed: unknown env names error out,
   the context is repo-declared data rather than a CLI argument, and a
   context pointing at the wrong machine is caught before `up`.

6. **Reach siblings by project-unique names.** Docker gives every container
   its service name as an alias on every network it joins, so on the shared
   `proxy` network a generic name like `web` or `api` resolves to other
   projects' containers too. A service on `proxy` that calls a sibling (e.g. a
   gateway proxying to the app) must use a project-unique network alias on the
   project's default network, such as `myapp-api`:

   ```yaml
   services:
     api:
       networks:
         default:
           aliases:
             - myapp-api
   ```

## Visitor IP

Remote traffic arrives through Cloudflare, which sets `CF-Connecting-IP` to
the visitor's address; the proxy passes the header through, so projects read
the visitor IP from `CF-Connecting-IP` with no extra labels. Trust it only on
servers where `just firewall` has completed with `CLOUDFLARE_ONLY=true`: there
the firewall lets only Cloudflare reach the origin, and Cloudflare always
overwrites the header. The flag alone proves nothing: if `just firewall`
refused, the origin is not Cloudflare-only. On a host with a global IPv6
address this requires the `proxy` network to have IPv6 enabled, since
otherwise `just firewall` refuses to apply. On other servers anyone who finds
the origin IP can send the header with any value, so per-IP rate limits and
logs keyed on it can be fooled.

## Full example

The project layout:

```
infra/compose.yml        # invariants: web service, proxy network, .localhost labels
envs/
  local/compose.yml      # dev delta: local db, mounts, watch (no server.conf → local)
  prod/
    server.conf          # DOCKER_CONTEXT=, SERVER_NAME=, PROTECTED=true
    compose.yml          # real domain, hardening, db if self-hosted
    .env                 # secrets (gitignored; CI writes it from the ENV_FILE secret)
```

`infra/compose.yml` — the shared truth, local-safe:

```yaml
services:
  web:
    build: .
    environment:
      - PORT=3000
    networks:
      - default
      - proxy
    labels:
      caddy: myapp.localhost
      caddy.reverse_proxy: "{{upstreams 3000}}"

networks:
  proxy:
    external: true
```

`envs/prod/compose.yml` — the env delta (real domain, production hardening):

```yaml
services:
  web:
    restart: unless-stopped
    mem_limit: 512m
    labels:
      caddy: myapp.com
```

Services that differ per environment (a local postgres vs a managed
database) are declared in the env overlays that need them, not in the base:
an overlay can override and add, but not remove, so the base holds only what
is true everywhere. (`!reset null` exists as an escape hatch for one-off
removals.)
