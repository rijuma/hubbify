# Follow-ups from Give the proxy network IPv6 on servers, split built firewall docs out of "Server bootstrap (planned)"

Issues noticed while implementing and reviewing the plan; none were in
scope. Review, delete what does not matter, then `/plan-steps FOLLOW-UPS.md`.

- `justfile:154` (firewall refusal message) and `docs/architecture.md:218-219` (§Firewall) — both say Docker's ip6tables support is "on unless `/etc/docker/daemon.json` sets `"ip6tables": false`", which only holds for Docker 27+; this plan added an explicit Docker <27 path (`network create --ipv6 --subnet`, `justfile:194`, architecture.md recreate step 3) without saying older daemons also need `"ip6tables": true` set in `daemon.json`, so an operator on an old daemon follows the documented steps and `just firewall` still refuses with advice that tells them ip6tables is already on; the "fresh servers pass the check" claim (architecture.md:226) has the same hidden condition (steps 1, 2) (close-out) (recurring)
