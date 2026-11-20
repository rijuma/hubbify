---
"hubbify": patch
---

The proxy is now built on Caddy 2.11.9 (builder and runtime images, both
pinned by digest). The release workflow moves to `changesets/action` v2, with
its inputs renamed to `publish-script`, `pr-title` and `commit-message`.
