# Firewall: only Cloudflare may reach the proxy

Working spec for a hubbify plan (turn it into `PLAN.md`, then delete this
file once the result is described in `docs/architecture.md`).

## Problem

Remote servers sit behind Cloudflare's proxy (orange cloud, see
`docs/architecture.md` → TLS), but the hubbify proxy publishes 80/443 on the
host to anyone. Whoever learns the origin IP can skip Cloudflare entirely:

- **Spoofed client IP.** Cloudflare sets `CF-Connecting-IP` (and
  `X-Forwarded-For`) to the real visitor IP. A direct request can set those
  headers to anything, and Caddy passes them through. Projects that rate
  limit or log by IP (for example smu-platform, whose gateway turns
  `CF-Connecting-IP` into `X-Real-IP` for its api) can be fooled: per-IP
  limits are bypassed, or one victim IP gets locked out.
- **No Cloudflare protection.** DDoS mitigation, WAF rules and caching only
  apply to traffic that goes through Cloudflare.

Nothing in hubbify restricts this today. The planned bootstrap mentions
`ufw (ssh/80/443)`, but that alone does not help:

- **Docker bypasses ufw for published ports.** Docker writes its own
  iptables rules (`DOCKER` chain in `nat`/`filter`), which run before ufw's
  `INPUT` rules, so `ufw deny`/`allow from` rules do not apply to the proxy's
  80/443. Filtering container traffic has to happen in the `DOCKER-USER`
  chain (or in ufw's `after.rules`, which can feed `DOCKER-USER`).

## Goal

On servers that opt in, only Cloudflare's IP ranges can open connections to
the proxy's 80/443 (TCP, and UDP 443 for HTTP/3). Everything else is dropped.
`CF-Connecting-IP` can then be trusted by every project, because only
Cloudflare can reach the origin and Cloudflare always overwrites it.

## Requirements

1. **Opt-in per server**, e.g. `CLOUDFLARE_ONLY=true` in
   `servers/<name>/server.env`. A server that also hosts grey-cloud (DNS
   only) domains must be able to keep 80/443 open.
2. **Cover IPv4 and IPv6**: the lists at `https://www.cloudflare.com/ips-v4`
   and `https://www.cloudflare.com/ips-v6`.
3. **Apply where Docker cannot bypass it**: `DOCKER-USER` (both `iptables`
   and `ip6tables`), matching on the original destination port
   (`-m conntrack --ctorigdstport`), since DNAT has already rewritten the
   port when `DOCKER-USER` runs. Allow established/related traffic first so
   the containers' own outbound connections keep working.
4. **Survive reboots and Docker restarts.** Docker creates `DOCKER-USER`
   empty on start and leaves existing rules alone, but plain iptables rules
   are lost on reboot. Persist them (ufw `after.rules` / `after6.rules`, or
   another mechanism the bootstrap installs).
5. **Refreshable from the client.** Cloudflare's ranges change rarely but do
   change. A `just` recipe (e.g. `just firewall <server>`) fetches the lists
   on the client and applies them over SSH, idempotently. Running it from
   `just upgrade` keeps it current. Per the hubbify rules: no scripts or
   cron jobs installed on the server, no server-side agent.
6. **Don't lock out SSH.** Only 80/443 are restricted; SSH stays as the
   bootstrap configures it. The recipe must not touch other rules.
7. **Local untouched.** Nothing changes for the local stack.
8. **ACME keeps working.** Certificates use DNS-01 (no inbound challenge
   traffic), so closing 80 to non-Cloudflare IPs is safe. Confirm the
   recipe doesn't break renewal.

## Nice to have: real client IP in Caddy

With the firewall in place, also make the proxy itself see the visitor:

- Global `servers` options in `proxy/Caddyfile.remote`: `trusted_proxies`
  with the Cloudflare ranges (static list, or the
  `github.com/WeidiDeng/caddy-cloudflare-ip` module, which needs adding to
  `proxy/Dockerfile`) and `client_ip_headers CF-Connecting-IP`. Access logs
  and `{client_ip}` then show the real visitor.
- Decide and document in `docs/project-contract.md` which header projects
  should read for the visitor IP (`CF-Connecting-IP` once the firewall is on,
  or a normalized `X-Forwarded-For`). This must not need extra `caddy.*`
  labels (contract rule 3).

## Alternatives considered

| Option                                  | For                                                    | Against                                                                                                                  |
| --------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| **IP allowlist in `DOCKER-USER`**       | Simple, no Cloudflare config, fits the bootstrap       | IP lists need refreshing; per-server opt-in for grey-cloud domains                                                       |
| Authenticated Origin Pulls (mTLS)       | Cryptographic, no IP lists; Cloudflare presents a cert | Per-site `tls client_auth`, which can't go in labels; must be enabled per zone in Cloudflare                             |
| Cloudflare Tunnel (`cloudflared`)       | No inbound ports at all; hides the origin              | Changes the architecture (tunnel container, CNAME DNS), replaces DNS-01/Caddy TLS assumptions; another moving part       |
| Caddy-only (`trusted_proxies` + header) | Real client IP in logs                                 | Doesn't stop direct traffic; projects reading `CF-Connecting-IP` can still be spoofed unless Caddy overwrites the header |

Recommended: the `DOCKER-USER` allowlist (requirements above), plus the
Caddy client-IP options.

## Acceptance

- From a non-Cloudflare IP, `curl -sk --resolve <domain>:443:<origin-ip> https://<domain>/`
  times out (TCP and HTTP/3).
- Through Cloudflare, every hosted domain still works.
- Rules are present after a reboot and after `systemctl restart docker`.
- Running the recipe twice leaves the same rule set (idempotent).
- Containers' outbound traffic (package installs, APIs) still works.
- A server without `CLOUDFLARE_ONLY=true` behaves exactly as before.
- `docs/architecture.md` (TLS / Server bootstrap sections) and
  `docs/project-contract.md` describe the final behavior; a changeset is
  added.

## Who asked

smu-platform (`~/projects/smu/smu-platform`) is moving its deploy onto
hubbify and rate-limits auth endpoints by client IP. Its plan assumes the
origin only accepts Cloudflare traffic; until this lands, its per-IP limits
can be bypassed by anyone who finds the origin IP.
