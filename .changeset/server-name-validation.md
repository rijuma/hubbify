---
"hubbify": patch
---

Server names are validated: `firewall`, `server-create`, `server-remove`,
`remote-up`, `remote-logs` and `upgrade` accept only lowercase letters, digits
and hyphens, starting with a letter or digit, so a name such as `../docs` can
no longer reach a path outside `servers/`.
