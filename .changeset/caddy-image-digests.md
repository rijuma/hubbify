---
"hubbify": patch
---

The proxy's Caddy base images (`caddy:2.11.2-builder` and
`caddy:2.11.2-alpine` in `proxy/Dockerfile`) are now pinned by tag and digest,
like the socket proxy, so a re-pushed tag cannot change the proxy image
without a diff. Dependabot's `docker` entry keeps the digests current.
