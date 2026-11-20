---
"hubbify": patch
---

The server recipes (`firewall`, `server-create`, `server-remove`, `remote-up`,
`remote-logs` and `upgrade`) now reject the server name `local`, which is
reserved for the local proxy's `servers/local/` folder.
