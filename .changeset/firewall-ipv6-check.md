---
"hubbify": patch
---

`just firewall` now refuses to apply the Cloudflare-only rules on a server with
a global IPv6 address unless Docker routes IPv6 through `DOCKER-USER` (Docker's
ip6tables support on and a `proxy` network with IPv6); otherwise IPv6 traffic
to 80/443 would bypass the filter. The message lists how to recreate the
`proxy` network with IPv6. `just upgrade` now reports a pending reboot before
refreshing the firewall, so a firewall refusal still fails it without hiding
that report.
