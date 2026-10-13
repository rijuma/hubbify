# Follow-ups from Per-server Caddyfile, then a Cloudflare-only firewall

Issues noticed while implementing and reviewing the plan; none were in
scope. Review, delete what does not matter, then `/plan-steps FOLLOW-UPS.md`.

- `docs/architecture.md` → Server bootstrap / `docs/project-contract.md` → Visitor IP — the IPv6 half of `just firewall` only works when Docker's own `ip6tables` support is on; with it off, published IPv6 traffic goes through docker-proxy and ufw's `INPUT` (where the bootstrap allows 80/443), never reaching `DOCKER-USER`, so the v6 block does nothing — yet the contract tells projects `CF-Connecting-IP` is trustworthy on every `CLOUDFLARE_ONLY` server, which is false on such a host with an IPv6 address; document the requirement (or have `just firewall` check it) and verify on pachuca (steps 5, 6)
- `AGENTS.md:32` and `docs/architecture.md:195` — still say hubbify "holds no project config" / "does not manage project config", but `servers/<name>/caddy/Caddyfile` now holds per-project site extras (e.g. pachuca's `docs.smu.ar` basic_auth hash); the Servers section was reworded for this, these two were not, so agents reading the hard rules get a false statement (steps 2, close-out)
