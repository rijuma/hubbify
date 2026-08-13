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
   `.localhost` domain in `compose.yml`:

   ```yaml
   labels:
     caddy: myapp.localhost
     caddy.reverse_proxy: "{{upstreams 3000}}"
   ```

   `caddy` is the domain; the number in `{{upstreams N}}` is the container
   port the app listens on. The remote overlay `compose.remote.yml` overrides
   only the domain label (compose merges labels by key):

   ```yaml
   labels:
     caddy: myapp.com
   ```

   A bare `docker compose up` therefore always serves `.localhost` — no env
   vars, no flags — while deploys always pass both files
   (`-f compose.yml -f compose.remote.yml`), so the real domain cannot be
   forgotten. The local domain must be the baseline: if the real domain were
   the default, a local run would attempt real ACME challenges.

3. **No other `caddy.*` labels.** If a project needs more than
   domain + port (extra headers, auth, redirects), that config goes into the
   proxy's base Caddyfile (`proxy/Caddyfile.remote`), written as plain
   Caddyfile — never as label trees.

4. **Do not publish ports.** The proxy reaches the app over the `proxy`
   network; only the proxy binds 80/443 on the host.

## Full example

`compose.yml` — the local truth:

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

  db:
    image: postgres:17-alpine
    # default network only — invisible to the proxy and other projects

networks:
  proxy:
    external: true
```

`compose.remote.yml` — the remote delta (real domain, production hardening):

```yaml
services:
  web:
    restart: unless-stopped
    mem_limit: 512m
    labels:
      caddy: myapp.com
```
