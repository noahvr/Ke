FROM debian:12-slim

# Install the Stork server from ISC's official Cloudsmith package repository.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/setup.deb.sh' | bash \
    && apt-get update \
    && apt-get install -y --no-install-recommends isc-stork-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080

# Database connection and other settings come from STORK_DATABASE_* /
# STORK_SERVER_* environment variables (see docker-compose.yml). The server
# runs its own database migrations on startup.
CMD ["/usr/bin/stork-server"]
