---
"hubbify": minor
---

Cloudflare-only firewall: `just firewall <server>` restricts inbound 80/443 to
Cloudflare's IP ranges on servers with `CLOUDFLARE_ONLY=true` in their
`server.env` (rules in ufw's `after.rules`/`after6.rules`, feeding
`DOCKER-USER`), lifts the restriction when the flag is cleared, and runs from
`just upgrade` to keep the ranges current. The remote proxy trusts Cloudflare's
ranges and reads the client IP from `CF-Connecting-IP`, and the project
contract documents that header as the visitor IP, trustworthy only on
`CLOUDFLARE_ONLY` servers.
