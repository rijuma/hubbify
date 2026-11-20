---
"hubbify": patch
---

Dependency refresh: the proxy is built on Caddy 2.11.9 (builder and runtime
images, both pinned by digest) with caddy-docker-proxy 2.13.1. The repo's own
tooling moves to pnpm 12, Changesets CLI 3 and `changesets/action` v2. Pinned
versions are bumped by hand; there is no Dependabot config.
