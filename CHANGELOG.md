# hubbify

## 0.2.0

### Minor Changes

- [`722a9cb`](https://github.com/rijuma/hubbify/commit/722a9cbc7d694ffb8d7a5b0a6525dbb774fe1a12) by [@rijuma](https://github.com/rijuma) - `ALLOW_INTERFACES` in `server.env` lists network interfaces whose traffic may
  reach 80/443 on a `CLOUDFLARE_ONLY` server, for example `tailscale0`. A server
  can then stay closed to the public while serving DNS-only sites inside a
  tailnet.

- [`11a2efc`](https://github.com/rijuma/hubbify/commit/11a2efc20a13a0459757bdf9a2ac506ac6581115) by [@rijuma](https://github.com/rijuma) - On a `CLOUDFLARE_ONLY` server, `just firewall` now drops every published port
  that is not explicitly allowed, not only 80 and 443 from outside Cloudflare.
  Docker forwards published ports past ufw, so a container started with `-p` on
  such a server was reachable from the internet. Run `just firewall <name>` to
  apply it to an existing server.

- [`4a1e191`](https://github.com/rijuma/hubbify/commit/4a1e191e4fcd18c13ecc7ee41389e5c3ec8343af) by [@rijuma](https://github.com/rijuma) - `just server-edit <name>` opens a server's `server.env` in `$VISUAL` or
  `$EDITOR` and, when it changed, publishes it to the server's 1Password vault
  (if it has a `source`) and runs `remote-up`, so a rotated token reaches the
  proxy in one step. It stops before opening the editor when the local folder
  differs from the shared copy.

- [`bbf25f6`](https://github.com/rijuma/hubbify/commit/bbf25f699f1d132dd1a8379e84ac3d9d0aa39134) by [@rijuma](https://github.com/rijuma) - A server folder can keep a shared copy of its `server.env` and Caddyfile in a
  1Password vault, named in a `source` file as `op://<vault>`. `just server-push`
  publishes the local files, `just server-pull` takes the shared ones, and
  `just server-create <name> op://<vault>` sets a server up from them. `remote-up`,
  `remote-logs`, `firewall` and `upgrade` stop when the local files differ from the
  shared copy. Servers without a `source` file are unchanged.

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

- [`eb1e726`](https://github.com/rijuma/hubbify/commit/eb1e726e29bc30d8412f4798dd16daf7505a2614) by [@rijuma](https://github.com/rijuma) - Project contract: beside the two routing labels, a project may now declare
  `caddy.basic_auth.<user>`, `caddy.header.<Name>` and `caddy.respond` to guard
  an environment (basic auth, a response header, a refused path), so that config
  ships with the project's deploy instead of living in the server's
  `servers/<name>/caddy/Caddyfile`. Any other `caddy.*` label stays out.

- [`c1d8e13`](https://github.com/rijuma/hubbify/commit/c1d8e139543ebf3e41b61abace887cdf4cf88964) by [@rijuma](https://github.com/rijuma) - Local Caddyfile extras: an optional `servers/local/caddy/Caddyfile` is appended
  to the local base Caddyfile when `just up` builds the proxy, the same way a
  server's `servers/<name>/caddy/Caddyfile` is appended on `just remote-up`. Site
  extras (auth, headers, redirects) can now be tried on a project's `.localhost`
  domain before they reach a server. `local` is no longer available as a server
  name.

- [`6a5616b`](https://github.com/rijuma/hubbify/commit/6a5616b25238e26de67715523382a25d270f482b) by [@rijuma](https://github.com/rijuma) - Per-server Caddyfile: an optional `servers/<name>/caddy/Caddyfile` is appended
  to the remote base Caddyfile when the proxy image is built, so extra site
  config (auth, headers, redirects) applies only to the server that hosts the
  site. The project contract now points there instead of
  `proxy/Caddyfile.remote`, and adds a rule that services on the shared `proxy`
  network reach their siblings only by project-unique network aliases.

- [`529c59c`](https://github.com/rijuma/hubbify/commit/529c59ccc0282c11b3a040be892dbbe1c17f77c6) by [@rijuma](https://github.com/rijuma) - The Caddy container no longer mounts the Docker socket. It reads the Docker API
  through a new `socket-proxy` service (`tecnativa/docker-socket-proxy`, pinned
  by digest) on an internal `docker-api` network; the socket proxy mounts the
  socket read-only and allows only GET requests on containers, networks, info,
  events, ping and version, so a label can no longer make Caddy send write
  requests to the daemon. Caddy also runs with every capability dropped except
  `NET_BIND_SERVICE`, and with `no-new-privileges`. No other API section had to
  be enabled. Servers pick the change up with `just upgrade <server>` or
  `just remote-up <server>`.

### Patch Changes

- [`751ed06`](https://github.com/rijuma/hubbify/commit/751ed06a4e11f95d17b0bd50ab652dff3971b699) by [@rijuma](https://github.com/rijuma) - Dependency refresh: the proxy is built on Caddy 2.11.9 (builder and runtime
  images, both pinned by digest) with caddy-docker-proxy 2.13.1. The repo's own
  tooling moves to pnpm 12, Changesets CLI 3 and `changesets/action` v2. Pinned
  versions are bumped by hand; there is no Dependabot config.

- [`b8b92d4`](https://github.com/rijuma/hubbify/commit/b8b92d47a240638b9a67641c283d512a42aa98f0) by [@rijuma](https://github.com/rijuma) - The proxy's Caddy base images (`caddy:2.11.2-builder` and
  `caddy:2.11.2-alpine` in `proxy/Dockerfile`) are now pinned by tag and digest,
  like the socket proxy, so a re-pushed tag cannot change the proxy image
  without a diff.

- [`4cc90e5`](https://github.com/rijuma/hubbify/commit/4cc90e5e1b25f4fe2a420acc7f7c90aaf7f754bc) by [@rijuma](https://github.com/rijuma) - The trust model in `docs/project-contract.md` now states that a deploy key's
  Docker access is root-equivalent on the server, and that the read-only socket
  proxy limits only what a label can do through Caddy.

- [`519758b`](https://github.com/rijuma/hubbify/commit/519758b65b58b52977252ede90f7b11596e2ea94) by [@rijuma](https://github.com/rijuma) - `just firewall` now refuses to apply the Cloudflare-only rules on a server with
  a global IPv6 address unless Docker routes IPv6 through `DOCKER-USER` (Docker's
  ip6tables support on and a `proxy` network with IPv6); otherwise IPv6 traffic
  to 80/443 would bypass the filter. The message lists how to recreate the
  `proxy` network with IPv6. `just upgrade` now reports a pending reboot before
  refreshing the firewall, so a firewall refusal still fails it without hiding
  that report.

- [`09373e5`](https://github.com/rijuma/hubbify/commit/09373e52b7257ab4edb6ec62dd8742e77a8d9ba6) by [@rijuma](https://github.com/rijuma) - CI and Release workflows: every GitHub Action is pinned by its full commit SHA,
  with the release tag kept as a trailing comment, so a moved or compromised tag
  cannot change what the workflows run.

- [`e800a67`](https://github.com/rijuma/hubbify/commit/e800a678987d25b9dc4f68b5e83f483716de15ef) by [@rijuma](https://github.com/rijuma) - `just remote-up` now creates the server's `proxy` network with IPv6, so fresh
  servers with a global IPv6 address pass the `just firewall` IPv6 check.
  `remote-up` requires Docker 27+ on the server and aborts with a clear message
  otherwise. Existing servers whose `proxy` network was created without IPv6 need
  the network recreated, as listed by `just firewall` and in
  `docs/architecture.md`.

- [`ca038dc`](https://github.com/rijuma/hubbify/commit/ca038dc89dfa36be22bf0968ab8787ab38839633) by [@rijuma](https://github.com/rijuma) - The server recipes (`firewall`, `server-create`, `server-remove`, `remote-up`,
  `remote-logs` and `upgrade`) now reject the server name `local`, which is
  reserved for the local proxy's `servers/local/` folder.

- [`259173b`](https://github.com/rijuma/hubbify/commit/259173b90efa508333293756239ebb8d865ec146) by [@rijuma](https://github.com/rijuma) - Server names are validated: `firewall`, `server-create`, `server-remove`,
  `remote-up`, `remote-logs` and `upgrade` accept only lowercase letters, digits
  and hyphens, starting with a letter or digit, so a name such as `../docs` can
  no longer reach a path outside `servers/`.

- [`0d60961`](https://github.com/rijuma/hubbify/commit/0d60961718e88c4ac45cf13d19a6aa0596ec52d0) by [@rijuma](https://github.com/rijuma) - Docs: the project contract now has a trust model section. Labels are a
  trusted channel, so anyone who can deploy to a server can read the proxy's
  `CLOUDFLARE_API_TOKEN`. If several servers share one token scoped to all
  zones, replace it with one token per server, limited to Zone → DNS → Edit on
  the zones that server hosts, and update each `servers/<name>/server.env`.
  The docs also state the limits of the shared `proxy` network and that
  container env is stored in Docker's container config on the server.

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
