FROM debian:12-slim

# Kea major.minor line to install; must ship kea-dhcp4 >= 2.7.9 so the DHCP
# daemon can expose the HTTP control socket directly (kea-ctrl-agent was
# removed upstream and no longer exists in Kea >= 3.2).
ARG KEA_REPO=kea-3-2

# Kea + open source hooks from isc/kea-3-2, Stork agent from isc/stork —
# both official ISC Cloudsmith repositories. perfdhcp is installed when the
# repo provides it as a separate package (used by the optional traffic
# generator service).
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates supervisor procps \
    && curl -1sLf "https://dl.cloudsmith.io/public/isc/${KEA_REPO}/setup.deb.sh" | bash \
    && curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/setup.deb.sh' | bash \
    && apt-get update \
    && apt-get install -y --no-install-recommends isc-kea-dhcp4 isc-kea-hooks isc-kea-admin isc-stork-agent \
    && (apt-get install -y --no-install-recommends isc-kea-perfdhcp || true) \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8080: Stork agent gRPC (server -> agent)
# 9547: Stork agent's Kea Prometheus exporter
# 67/udp: DHCPv4
EXPOSE 8080 9547 67/udp

ENTRYPOINT ["/entrypoint.sh"]
