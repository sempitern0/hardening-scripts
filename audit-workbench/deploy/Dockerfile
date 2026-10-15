# Deployment image: serve ONLY the PWA shell. Never copy audit data or Discovery executables.
FROM caddy:2-alpine

COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY index.html sw.js manifest.webmanifest /srv/
COPY css/ /srv/css/
COPY js/ /srv/js/
COPY fonts/ /srv/fonts/
COPY icons/ /srv/icons/

RUN mkdir -p /data /config /srv && \
    chown -R 10001:10001 /data /config /srv /etc/caddy/Caddyfile
USER 10001:10001
EXPOSE 8080 8443
