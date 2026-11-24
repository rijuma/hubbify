---
"hubbify": minor
---

On a `CLOUDFLARE_ONLY` server, `just firewall` now drops every published port
that is not explicitly allowed, not only 80 and 443 from outside Cloudflare.
Docker forwards published ports past ufw, so a container started with `-p` on
such a server was reachable from the internet. Run `just firewall <name>` to
apply it to an existing server.
