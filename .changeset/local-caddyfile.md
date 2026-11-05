---
"hubbify": minor
---

Local Caddyfile extras: an optional `servers/local/caddy/Caddyfile` is appended
to the local base Caddyfile when `just up` builds the proxy, the same way a
server's `servers/<name>/caddy/Caddyfile` is appended on `just remote-up`. Site
extras (auth, headers, redirects) can now be tried on a project's `.localhost`
domain before they reach a server. `local` is no longer available as a server
name.
