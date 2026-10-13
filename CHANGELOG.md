# hubbify

## 0.1.0

### Minor Changes

- [`bd53547`](https://github.com/rijuma/hubbify/commit/bd53547387ec9b45b473c4377a92eceed0ebceee) by [@rijuma](https://github.com/rijuma) - Cloudflare-only firewall: `just firewall <server>` restricts inbound 80/443 to
  Cloudflare's IP ranges on servers with `CLOUDFLARE_ONLY=true` in their
  `server.env` (rules in ufw's `after.rules`/`after6.rules`, feeding
  `DOCKER-USER`), lifts the restriction when the flag is cleared, and runs from
  `just upgrade` to keep the ranges current. The remote proxy trusts Cloudflare's
  ranges and reads the client IP from `CF-Connecting-IP`, and the project
  contract documents that header as the visitor IP, trustworthy only once
  `just firewall` has completed with `CLOUDFLARE_ONLY=true`, which on a host with
  a global IPv6 address needs a `proxy` network with IPv6.

- [`6a5616b`](https://github.com/rijuma/hubbify/commit/6a5616b25238e26de67715523382a25d270f482b) by [@rijuma](https://github.com/rijuma) - Per-server Caddyfile: an optional `servers/<name>/caddy/Caddyfile` is appended
  to the remote base Caddyfile when the proxy image is built, so extra site
  config (auth, headers, redirects) applies only to the server that hosts the
  site. The project contract now points there instead of
  `proxy/Caddyfile.remote`, and adds a rule that services on the shared `proxy`
  network reach their siblings only by project-unique network aliases.

### Patch Changes

- [`519758b`](https://github.com/rijuma/hubbify/commit/519758b65b58b52977252ede90f7b11596e2ea94) by [@rijuma](https://github.com/rijuma) - `just firewall` now refuses to apply the Cloudflare-only rules on a server with
  a global IPv6 address unless Docker routes IPv6 through `DOCKER-USER` (Docker's
  ip6tables support on and a `proxy` network with IPv6); otherwise IPv6 traffic
  to 80/443 would bypass the filter. The message lists how to recreate the
  `proxy` network with IPv6. `just upgrade` now reports a pending reboot before
  refreshing the firewall, so a firewall refusal still fails it without hiding
  that report.

- [`e800a67`](https://github.com/rijuma/hubbify/commit/e800a678987d25b9dc4f68b5e83f483716de15ef) by [@rijuma](https://github.com/rijuma) - `just remote-up` now creates the server's `proxy` network with IPv6, so fresh
  servers with a global IPv6 address pass the `just firewall` IPv6 check.
  `remote-up` requires Docker 27+ on the server and aborts with a clear message
  otherwise. Existing servers whose `proxy` network was created without IPv6 need
  the network recreated, as listed by `just firewall` and in
  `docs/architecture.md`.

## 0.0.2

### Patch Changes

- [`1f29b86`](https://github.com/rijuma/hubbify/commit/1f29b86746d11f143e9cd1a2bd65e66809685ff1) by [@rijuma](https://github.com/rijuma) - Stamp every server's proxy with a `hubbify.server: <SERVER_NAME>` label (new
  `SERVER_NAME` in `servers/<name>/server.env`) so project deploys can verify
  they are pointed at the intended server before running `up`. Project contract
  updated for the per-environment layout (`envs/<env>/` with `server.conf`)
  used by hubbify-template.

## 0.0.1

### Patch Changes

- [`cd50a72`](https://github.com/rijuma/hubbify/commit/cd50a72ac1ccdf89c70c379af037ed7493ce2986) by [@rijuma](https://github.com/rijuma) - Initial release: Caddy reverse proxy with the two-label project contract,
  multi-server management (`servers/<name>/`), SSH docker-context deploys, and
  host maintenance recipes.
