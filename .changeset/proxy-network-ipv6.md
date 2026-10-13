---
"hubbify": patch
---

`just remote-up` now creates the server's `proxy` network with IPv6 (needs
Docker 27 or later; on older daemons it fails with a hint to create the network
by hand with `--subnet`), so fresh servers with a global IPv6 address pass the
`just firewall` IPv6 check. Existing servers whose `proxy` network was created
without IPv6 need the network recreated, as listed by `just firewall` and in
`docs/architecture.md`.
