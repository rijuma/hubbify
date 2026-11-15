---
"hubbify": minor
---

Project contract: beside the two routing labels, a project may now declare
`caddy.basic_auth.<user>`, `caddy.header.<Name>` and `caddy.respond` to guard
an environment (basic auth, a response header, a refused path), so that config
ships with the project's deploy instead of living in the server's
`servers/<name>/caddy/Caddyfile`. Any other `caddy.*` label stays out.
