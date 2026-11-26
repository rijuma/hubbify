---
"hubbify": minor
---

`just server-edit <name>` opens a server's `server.env` in `$VISUAL` or
`$EDITOR` and, when it changed, publishes it to the server's 1Password vault
(if it has a `source`) and runs `remote-up`, so a rotated token reaches the
proxy in one step. It stops before opening the editor when the local folder
differs from the shared copy.
