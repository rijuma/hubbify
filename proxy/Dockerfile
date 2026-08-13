FROM caddy:2.11.2-builder AS builder

RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.12.0 \
    --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Base Caddyfiles are baked into the image (not bind-mounted) so the same
# build works over a remote docker context, where the repo doesn't exist on
# the server. CADDY_DOCKER_CADDYFILE_PATH selects local vs remote.
COPY Caddyfile Caddyfile.remote /etc/caddy/

CMD ["caddy", "docker-proxy"]
