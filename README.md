# hubbify

A simple toolkit to set up and maintain VPS servers hosting docker-compose
projects behind a single reverse proxy — the same proxy, config, and workflow
locally and in production.

Start with [docs/architecture.md](docs/architecture.md). To host a project,
follow [docs/project-contract.md](docs/project-contract.md).

## Quickstart (local)

```sh
just up      # build + start the proxy (first build compiles Caddy, takes a bit)
just trust   # trust Caddy's local CA so browsers accept https://*.localhost
```

Then create your project from
[hubbify-template](https://github.com/rijuma/hubbify-template) ("Use this
template") — it ships a working app already honoring the
[project contract](docs/project-contract.md), served at
`https://<name>.localhost` behind this proxy.

`just --list` shows all recipes.

## Status

Working: the local and remote proxy stacks with the label-based project
contract, multi-server management (`servers/<name>/`), deploys over SSH
docker contexts, host maintenance recipes, and the opt-in Cloudflare-only
firewall. Planned next: server
bootstrap script, deploy-time Cloudflare DNS sync.
