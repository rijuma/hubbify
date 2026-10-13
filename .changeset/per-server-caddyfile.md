---
"hubbify": minor
---

Per-server Caddyfile: an optional `servers/<name>/caddy/Caddyfile` is appended
to the remote base Caddyfile when the proxy image is built, so extra site
config (auth, headers, redirects) applies only to the server that hosts the
site. The project contract now points there instead of
`proxy/Caddyfile.remote`, and adds a rule that services on the shared `proxy`
network reach their siblings only by project-unique network aliases.
