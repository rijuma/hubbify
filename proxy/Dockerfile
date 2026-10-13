FROM caddy:2.11.2-builder AS builder

RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v2.12.0 \
    --with github.com/caddy-dns/cloudflare@v0.2.4

# Optional per-server Caddyfile. compose.remote.yml replaces this empty stage
# with the servers/<name>/caddy/ folder as an additional build context.
FROM scratch AS server

# Appends the server's Caddyfile, when there is one, to the remote base.
# caddy-docker-proxy doesn't expand `import`, so the blocks must be inline.
FROM caddy:2.11.2-alpine AS caddyfiles
COPY Caddyfile.remote /etc/caddy/
COPY --from=server Caddyfil[e] /tmp/server/
RUN if [ -f /tmp/server/Caddyfile ]; then \
        printf '\n' >> /etc/caddy/Caddyfile.remote && \
        cat /tmp/server/Caddyfile >> /etc/caddy/Caddyfile.remote; \
    fi

FROM caddy:2.11.2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Base Caddyfiles are baked into the image (not bind-mounted) so the same
# build works over a remote docker context, where the repo doesn't exist on
# the server. CADDY_DOCKER_CADDYFILE_PATH selects local vs remote.
COPY Caddyfile /etc/caddy/
COPY --from=caddyfiles /etc/caddy/Caddyfile.remote /etc/caddy/

CMD ["caddy", "docker-proxy"]
