---
"hubbify": patch
---

CI and Release workflows: every GitHub Action is pinned by its full commit SHA,
with the release tag kept as a trailing comment, so a moved or compromised tag
cannot change what the workflows run.
