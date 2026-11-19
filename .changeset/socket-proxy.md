---
"hubbify": minor
---

The Caddy container no longer mounts the Docker socket. It reads the Docker API
through a new `socket-proxy` service (`tecnativa/docker-socket-proxy`, pinned
by digest) on an internal `docker-api` network; the socket proxy mounts the
socket read-only and allows only GET requests on containers, networks, info,
events, ping and version, so a label can no longer make Caddy send write
requests to the daemon. Caddy also runs with every capability dropped except
`NET_BIND_SERVICE`, and with `no-new-privileges`. No other API section had to
be enabled. Servers pick the change up with `just upgrade <server>` or
`just remote-up <server>`.
