# hubbify — agent guide

Toolkit for hosting docker-compose projects on VPS servers behind one Caddy
reverse proxy, identical locally and remotely. Read
`docs/architecture.md` first; it reflects the final design, including parts
marked "(planned)" that are not built yet.

## Commands

Everything goes through `just` (run `just --list`). Local: `up`, `down`,
`logs`. Remote recipes take a docker SSH context name, e.g.
`just remote-up myvps`. Server operations are always just recipes run from
the client, wrapping `docker --context` or one-off `ssh` commands — never
scripts installed on the server, never a server-side agent. Servers hold no
compose files or repos; the reasons (drift, credentials, secrets at rest,
disposability, CI parity) are in `docs/architecture.md` → Deploys.

## Hard rules

- **Two labels per project, never more.** Routing is declared only as
  `caddy: <domain>` + `caddy.reverse_proxy: '{{upstreams <port>}}'`
  (see `docs/project-contract.md`). Anything fancier goes in the hosting
  server's `servers/<name>/caddy/Caddyfile`, written as plain Caddyfile —
  never as `caddy.*` label trees.
- **Isolation:** only web-facing services join the external `proxy` network;
  databases/workers stay on the project default network. No project publishes
  host ports.
- **Secrets:** `CLOUDFLARE_API_TOKEN` lives in `servers/<name>/server.env`
  (gitignored) on the machine that runs the deploy — never committed, never
  stored on the server outside the proxy container's env. Project production
  envs are GitHub environment secrets in each project's own repo; hubbify
  holds no project config.

## Conventions

- Docs in `docs/` describe the current final state, not decision history.
  When a design changes, rewrite the doc; don't append changelogs.
- Keep it simple: plain `just` recipes and small scripts. No CLI framework,
  no config generators — that's what killed v1.
- This is a pre-release greenfield project: no backward-compat or migration
  shims; design for the end state.
- After editing any `.md` file, run `npx prettier --write` on it.
- Notable changes get a changeset (`pnpm changeset`). Releases are cut by the
  Release workflow: it opens a version PR that consumes pending changesets;
  merging it updates `CHANGELOG.md` and tags `v<version>`.
