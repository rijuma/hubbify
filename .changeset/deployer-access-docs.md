---
"hubbify": patch
---

The trust model in `docs/project-contract.md` now states that a deploy key's
Docker access is root-equivalent on the server, and that the read-only socket
proxy limits only what a label can do through Caddy.
