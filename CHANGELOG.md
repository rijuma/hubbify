# hubbify

## 0.0.2

### Patch Changes

- [`1f29b86`](https://github.com/rijuma/hubbify/commit/1f29b86746d11f143e9cd1a2bd65e66809685ff1) by [@rijuma](https://github.com/rijuma) - Stamp every server's proxy with a `hubbify.server: <SERVER_NAME>` label (new
  `SERVER_NAME` in `servers/<name>/server.env`) so project deploys can verify
  they are pointed at the intended server before running `up`. Project contract
  updated for the per-environment layout (`envs/<env>/` with `server.conf`)
  used by hubbify-template.

## 0.0.1

### Patch Changes

- [`cd50a72`](https://github.com/rijuma/hubbify/commit/cd50a72ac1ccdf89c70c379af037ed7493ce2986) by [@rijuma](https://github.com/rijuma) - Initial release: Caddy reverse proxy with the two-label project contract,
  multi-server management (`servers/<name>/`), SSH docker-context deploys, and
  host maintenance recipes.
