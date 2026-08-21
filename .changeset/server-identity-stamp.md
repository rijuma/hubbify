---
"hubbify": patch
---

Stamp every server's proxy with a `hubbify.server: <SERVER_NAME>` label (new
`SERVER_NAME` in `servers/<name>/server.env`) so project deploys can verify
they are pointed at the intended server before running `up`. Project contract
updated for the per-environment layout (`envs/<env>/` with `server.conf`)
used by hubbify-template.
