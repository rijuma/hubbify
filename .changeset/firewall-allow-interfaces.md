---
"hubbify": minor
---

`ALLOW_INTERFACES` in `server.env` lists network interfaces whose traffic may
reach 80/443 on a `CLOUDFLARE_ONLY` server, for example `tailscale0`. A server
can then stay closed to the public while serving DNS-only sites inside a
tailnet.
