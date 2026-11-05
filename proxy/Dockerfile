FROM caddy:2.11.2-builder AS builder

RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.12.0 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/WeidiDeng/caddy-cloudflare-ip@f53b62aa13cb7ad79c8b47aacc3f2f03989b67e5

# Optional per-server Caddyfile. The compose files replace this empty stage
# with a servers/<name>/caddy/ folder as an additional build context:
# servers/local/caddy/ locally, the server's own folder on a remote build.
FROM scratch AS server

# Appends that Caddyfile, when there is one, to both bases; each build only
# runs the base its compose file selects. caddy-docker-proxy doesn't expand
# `import`, so the blocks must be inline.
FROM caddy:2.11.2-alpine AS caddyfiles
COPY Caddyfile Caddyfile.remote /etc/caddy/
COPY --from=server Caddyfil[e] /tmp/server/
RUN if [ -f /tmp/server/Caddyfile ]; then \
        for base in Caddyfile Caddyfile.remote; do \
            printf '\n' >> /etc/caddy/$base && \
            cat /tmp/server/Caddyfile >> /etc/caddy/$base; \
        done; \
    fi

FROM caddy:2.11.2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Base Caddyfiles are baked into the image (not bind-mounted) so the same
# build works over a remote docker context, where the repo doesn't exist on
# the server. CADDY_DOCKER_CADDYFILE_PATH selects local vs remote.
COPY --from=caddyfiles /etc/caddy/Caddyfile /etc/caddy/Caddyfile.remote /etc/caddy/

CMD ["caddy", "docker-proxy"]
