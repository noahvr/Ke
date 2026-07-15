#!/bin/sh
set -e

# Kea refuses control sockets in insecure directories: /run/kea must exist,
# be owned by the user running Kea, and not be world-accessible.
mkdir -p /run/kea /var/lib/kea
chmod 750 /run/kea

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
