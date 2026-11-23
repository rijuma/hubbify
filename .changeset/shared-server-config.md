---
"hubbify": minor
---

A server folder can keep a shared copy of its `server.env` and Caddyfile in a
1Password vault, named in a `source` file as `op://<vault>`. `just server-push`
publishes the local files, `just server-pull` takes the shared ones, and
`just server-create <name> op://<vault>` sets a server up from them. `remote-up`,
`remote-logs`, `firewall` and `upgrade` stop when the local files differ from the
shared copy. Servers without a `source` file are unchanged.
