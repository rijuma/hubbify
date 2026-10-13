---
"hubbify": patch
---

`just remote-up` now creates the server's `proxy` network with IPv6, so fresh
servers with a global IPv6 address pass the `just firewall` IPv6 check.
`remote-up` requires Docker 27+ on the server and aborts with a clear message
otherwise. Existing servers whose `proxy` network was created without IPv6 need
the network recreated, as listed by `just firewall` and in
`docs/architecture.md`.
