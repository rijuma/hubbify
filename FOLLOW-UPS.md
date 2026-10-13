# Follow-ups from Close the IPv6 gap in just firewall, fix "no project config" wording

Issues noticed while implementing and reviewing the plan; none were in
scope. Review, delete what does not matter, then `/plan-steps FOLLOW-UPS.md`.

- `justfile:8` (`_network`) and `justfile:192` (`remote-up`) — the `proxy` network is still created without `--ipv6`, so every fresh server with a global IPv6 address and `CLOUDFLARE_ONLY=true` is guaranteed to hit the new `just firewall` refusal and needs the manual 6-step teardown/recreate on day one; the plan's Decisions kept this as an operator action, so it needs a decision (create with `--ipv6` when the host has global IPv6, or accept the manual path), not just another step (steps 1, 2) (recurring)
- `docs/architecture.md:211` — the "Server bootstrap (planned)" heading now holds built behaviour (the `DOCKER-USER` block and the new IPv6 check/way out of `just firewall`), while `CLAUDE.md` tells agents "(planned)" parts are not built, so readers get a false picture of what exists; split the built firewall material out of the planned section or reword the heading (step 2) (recurring)
