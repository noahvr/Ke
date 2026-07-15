# Kea + Stork + Prometheus stack

A docker-compose stack for managing and trending ISC Kea DHCP. Visualization
is done by an **external Grafana on another machine** (see below); this stack
only collects and stores the metrics.

| Service | Purpose | URL (defaults) |
|---|---|---|
| `kea` | Kea DHCPv4 server + Stork agent (Prometheus exporter on `:9547`) | — |
| `stork-server` | Stork management UI / REST API | http://localhost:8080 |
| `postgres` | Stork server database | — |
| `prometheus` | Time-series storage (180 d retention by default) | http://localhost:9090 |
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
3. **Prometheus** — http://localhost:9090/targets should show the `kea`
   (agent exporter, port 9547) and `stork-server` jobs as *UP*.
4. **Dashboards** — connect your external Grafana as described in the next
   section.

## Visualization with an external Grafana

Prometheus is published on `${PROMETHEUS_PORT:-9090}`, so a Grafana running
on another machine can query it directly. Make sure that port is reachable
from the Grafana machine (firewall/security group), then:

### 1. Add the Prometheus datasource

The Stork dashboards reference their datasource by the fixed UID
`PBFA97CFB590B2093`, and Grafana's UI does not let you choose a UID when
creating a datasource — so use one of these approaches:

- **Provisioning (recommended):** copy
  `grafana/provisioning/datasources/prometheus.yml` from this directory to
  `/etc/grafana/provisioning/datasources/kea-prometheus.yml` on the Grafana
  machine, replace `<stack-host>` with this host's address, and restart
  Grafana. The datasource is created with the correct UID and the dashboards
  work unmodified.
- **API:** create the datasource with an explicit UID:

  ```sh
  curl -X POST http://<grafana-host>:3000/api/datasources \
    -H 'Content-Type: application/json' -u admin:<password> -d '{
      "name": "Kea Prometheus", "type": "prometheus", "access": "proxy",
      "url": "http://<stack-host>:9090", "uid": "PBFA97CFB590B2093"
    }'
  ```

- **Existing datasource instead:** if you already have a Prometheus
  datasource (e.g. federated/central Prometheus scraping this one), rewrite
  the UID inside the dashboard JSONs before importing:

  ```sh
  sed -i 's/PBFA97CFB590B2093/<your-datasource-uid>/g' grafana/dashboards/*.json
  ```

### 2. Import the dashboards

- **UI import:** Dashboards → New → Import → upload
  `grafana/dashboards/kea-dhcp4.json` (and `kea-dhcp6.json` if you serve
  DHCPv6). These are ISC's official Stork dashboards.
- **Or provision them:** copy `grafana/provisioning/dashboards/stork.yml` to
  `/etc/grafana/provisioning/dashboards/` and the `grafana/dashboards/*.json`
  files to `/var/lib/grafana/dashboards/` on the Grafana machine, then
  restart Grafana.

Trends (pool utilization, leases/s, DISCOVER/OFFER/ACK rates, per-subnet
usage) accumulate as Prometheus scrapes — the dashboards fill in over time.

### Securing the Prometheus endpoint

Prometheus has no authentication of its own. On anything beyond a lab
network, restrict `${PROMETHEUS_PORT}` to the Grafana machine's address
(firewall rule), or bind it to a management network only, e.g.
`"10.0.0.5:9090:9090"` in `docker-compose.yml` — or drop the port mapping
entirely and have a central Prometheus federate/scrape the exporters
instead.

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
  proxy in front of Stork before exposing it beyond localhost.
- DHCP service on the compose bridge network only reaches the simulated
  clients. To serve real clients, run the `kea` service with
  `network_mode: host` (or macvlan) and set its subnet/pools to match your
  network; the Docker-specific `172.42.0.0/24` demo subnet in
  `kea-dhcp4.conf` then needs replacing.
- Lease *metrics* history lives in Prometheus (`PROMETHEUS_RETENTION` in
  `.env`). For a per-client lease audit trail (who had which IP when), add
  Kea's `libdhcp_legal_log.so` forensic-logging hook — that is a separate
  concern from the metrics pipeline.
- Versions: Prometheus is pinned in `docker-compose.yml`; the Kea package
  line is selected by the `KEA_REPO` build arg (`kea/Dockerfile`, default
  `kea-3-2`); the Stork packages track ISC's latest stable from the
  `isc/stork` Cloudsmith repo. The dashboards were exported from the Stork
  project and work on any reasonably current Grafana (v10+).
