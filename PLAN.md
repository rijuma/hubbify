# Plan: Say that Docker older than 27 needs ip6tables enabled by hand

Source: `FOLLOW-UPS.md` (sections referenced per step). Rests on: `docs/architecture.md` (§Firewall).

Workflow: `/next-step` does the first unchecked step and stops;
`/implement-steps` loops it and commits each step.

Verify after every step: `just --list >/dev/null` `pnpm exec prettier --check <changed .md files>`
On close, delete: `PLAN.md`, `FOLLOW-UPS.md`

## Decisions (do not reopen)

- Wording of the fact, to use everywhere it appears: Docker's ip6tables support is on by default from Docker 27; older daemons need `"ip6tables": true` in `/etc/docker/daemon.json` (daemons before 26.0 also `"experimental": true`), then a daemon restart. Keep it to one clause per place; no version-detection code in the recipes.
- This item is tagged recurring: fix every place that states or implies the ip6tables default in one step, so it stops coming back.

## Steps

- [ ] **1. Document the ip6tables requirement on Docker older than 27** — The `just firewall` refusal message (`justfile`, the `echo` lines around line 154 saying ip6tables is "on unless /etc/docker/daemon.json sets \"ip6tables\": false"), the `remote-up` failure message (`justfile` ~line 194, the Docker <27 `network create --ipv6 --subnet` advice), and `docs/architecture.md` §Firewall (lines ~217-240: the "on unless ... false" sentence, the "fresh servers pass the check" claim, and recreate step 3) all present ip6tables as on by default; rewrite each so an operator on Docker older than 27 is told to set `"ip6tables": true` in `/etc/docker/daemon.json` and restart Docker, per the Decisions wording. In the doc, qualify the "fresh servers pass the check" claim the same way (fresh servers on Docker 27+ pass). Add a changeset (`.changeset/<name>.md`, patch, matching the existing ones' format) describing the corrected guidance. Read: `FOLLOW-UPS.md` (the single bullet); `docs/architecture.md` §Firewall. Depends on: none. Touches: `justfile`, `docs/architecture.md`, `.changeset/`. Done when: `grep -q '"ip6tables": true' justfile`; `grep -q '"ip6tables": true' docs/architecture.md`; `! grep -n 'on unless' justfile docs/architecture.md`; `just --list >/dev/null`; `pnpm exec prettier --check docs/architecture.md '.changeset/*.md'`.
- [ ] **2. Close the plan** — delete the files listed under "On close" and nothing else. Depends on: all. Commit message: `docs: finished plan`.

## Done

<!-- /next-step moves finished steps here with a one-line result note. -->
