# Kea + Stork + Prometheus + Grafana stack

A self-contained docker-compose stack for managing and trending ISC Kea DHCP:

| Service | Purpose | URL (defaults) |
|---|---|---|
| `kea` | Kea DHCPv4 server + Stork agent (Prometheus exporter on `:9547`) | — |
| `stork-server` | Stork management UI / REST API | http://localhost:8080 |
| `postgres` | Stork server database | — |
| `prometheus` | Time-series storage (180 d retention by default) | http://localhost:9090 |
| `grafana` | Trend dashboards (Stork's official Kea dashboards pre-provisioned) | http://localhost:3000 |
| `dhcp-client-sim` | Optional `perfdhcp` traffic generator (profile `traffic`) | — |

Kea and the Stork agent run in one container (mirroring a real host, where the
agent runs next to Kea). Kea ≥ 3.2 has no `kea-ctrl-agent` anymore — the DHCPv4
daemon exposes its HTTP control socket directly on `127.0.0.1:8000` inside the
container, where the agent talks to it.

## Quick start

```sh
cd deploy/stork-stack
docker compose up -d --build

# with simulated DHCP traffic (nicer graphs):
docker compose --profile traffic up -d --build
```

Then:

1. **Stork UI** — http://localhost:8080, first login `admin` / `admin`
   (you will be prompted to change it).
2. **Authorize the agent** — Services → Machines → *Unauthorized* tab →
   authorize the `kea` machine. Within a minute the Kea app, its subnets, and
   pool utilization appear in the UI.
3. **Grafana** — http://localhost:3000, login `admin` / `admin` (or
   `GRAFANA_ADMIN_PASSWORD` from `.env`). The **Stork** folder contains the
   *Stork Kea DHCPv4* and *Stork Kea DHCPv6* dashboards, already wired to
   Prometheus. Trends (pool utilization, leases/s, message rates) accumulate
   as Prometheus scrapes.
4. **Prometheus** — http://localhost:9090/targets should show the `kea`
   (agent exporter, port 9547) and `stork-server` jobs as *UP*.

## Making manual DHCP changes

- **Through Stork**: the config loads `subnet_cmds` and `lease_cmds`, so
  subnets/pools are editable from the Stork UI and leases are searchable.
  `stat_cmds` provides the utilization statistics both Stork and the Grafana
  dashboards rely on.
- **By hand**: edit `kea/config/kea-dhcp4.conf` (bind-mounted read-write into
  the container) and reload with

  ```sh
  docker compose exec kea sh -c \
    'echo "{\"command\": \"config-reload\"}" | socat - UNIX:/run/kea/kea4-ctrl-socket'
  ```

  or simply `docker compose restart kea`.
- **Host reservations from Stork** need the `host_cmds` hook plus a MySQL or
  PostgreSQL host backend (`hosts-database`) — see the Kea ARM. File-based
  reservations remain hand-editable in the config.

## Using an existing / external Kea server instead

The bundled `kea` container is a lab instance. To monitor a Kea server running
elsewhere:

1. Install `isc-stork-agent` on that host (ISC Cloudsmith `isc/stork` repo).
2. Point it at this server: `STORK_AGENT_SERVER_URL=http://<this-host>:8080`
   in `/etc/stork/agent.env`, then start the agent and authorize it in the UI.
3. Add its exporter (`<kea-host>:9547`) to `prometheus/prometheus.yml`.
4. Make sure that Kea loads `libdhcp_stat_cmds.so` and exposes a control
   socket the agent can reach (unix socket or HTTP on localhost).

## Notes

- Credentials in `.env` are lab defaults — change them, and put a TLS reverse
  proxy in front of Stork/Grafana before exposing anything beyond localhost.
- DHCP service on the compose bridge network only reaches the simulated
  clients. To serve real clients, run the `kea` service with
  `network_mode: host` (or macvlan) and set its subnet/pools to match your
  network; the Docker-specific `172.42.0.0/24` demo subnet in
  `kea-dhcp4.conf` then needs replacing.
- Lease *metrics* history lives in Prometheus (`PROMETHEUS_RETENTION` in
  `.env`). For a per-client lease audit trail (who had which IP when), add
  Kea's `libdhcp_legal_log.so` forensic-logging hook — that is a separate
  concern from the metrics pipeline.
- Versions: Grafana and Prometheus are pinned in `docker-compose.yml`; the
  Kea package line is selected by the `KEA_REPO` build arg
  (`kea/Dockerfile`, default `kea-3-2`); the Stork packages track ISC's
  latest stable from the `isc/stork` Cloudsmith repo.
