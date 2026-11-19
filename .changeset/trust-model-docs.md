---
"hubbify": patch
---

Docs: the project contract now has a trust model section. Labels are a
trusted channel, so anyone who can deploy to a server can read the proxy's
`CLOUDFLARE_API_TOKEN`. If several servers share one token scoped to all
zones, replace it with one token per server, limited to Zone → DNS → Edit on
the zones that server hosts, and update each `servers/<name>/server.env`.
The docs also state the limits of the shared `proxy` network and that
container env is stored in Docker's container config on the server.
