# OpenSIPS 3.4 Docker — Dual-Interface SIP Proxy

Containerized OpenSIPS inline proxy for TransNexus ClearIP with separate LAN and WAN interfaces.

```
┌──────────┐      ┌─────────────────────────┐      ┌──────────┐
│          │      │       OpenSIPS           │      │          │
│  PBX /   │◄────►│                         │◄────►│   SIP    │
│  Phones  │ LAN  │  INTERNAL    EXTERNAL   │ WAN  │  Trunk   │
│          │      │  10.0.1.100  203.0.113.50│      │  (ITSP)  │
└──────────┘      └─────────────────────────┘      └──────────┘
                         │
                         ▼
                   TransNexus ClearIP
                   (STIR/SHAKEN)
```

## Quick Start

1. **Edit `docker-compose.yml`** — set your actual IPs:
   ```yaml
   - INTERNAL_IP=10.0.1.100      # Your LAN IP
   - EXTERNAL_IP=203.0.113.50    # Your WAN IP
   ```

2. **Build and run:**
   ```bash
   docker compose up -d --build
   ```

3. **Check logs:**
   ```bash
   docker logs -f opensips-clearip
   ```

## Environment Variables

| Variable            | Required | Default                    | Description                       |
|---------------------|----------|----------------------------|-----------------------------------|
| `INTERNAL_IP`       | Yes      | —                          | LAN-facing IP (PBX/phones)        |
| `EXTERNAL_IP`       | Yes      | —                          | WAN-facing IP (SIP trunks)        |
| `INTERNAL_PORT`     | No       | `5060`                     | SIP port on LAN interface         |
| `EXTERNAL_PORT`     | No       | `5060`                     | SIP port on WAN interface         |
| `EXTERNAL_TLS_PORT` | No       | `5061`                     | TLS port on WAN interface         |
| `SHM_MEMORY`        | No       | `1024`                     | Shared memory (MB)                |
| `PKG_MEMORY`        | No       | `4`                        | Package memory (MB)               |
| `TLS_CN`            | No       | `localhost`                | TLS certificate Common Name       |
| `CLEARIP_URL`       | No       | `https://api.clearip.com`  | TransNexus ClearIP API endpoint   |

## Networking

**Host networking is required** (`network_mode: host`) so the container can bind directly to your LAN and WAN IP addresses. The container sees all host network interfaces.

## Routing Logic

The config template uses OpenSIPS socket naming to determine traffic direction:

- **Inbound on `lan` socket** → Routed outbound via WAN (LAN-to-trunk)
- **Inbound on `wan` socket** → Routed inbound via LAN (trunk-to-PBX)
- **NAT detection** is applied to WAN-side traffic automatically
- **Record-routing** ensures mid-dialog requests (re-INVITEs, BYEs) traverse the proxy

## ClearIP Integration (STIR/SHAKEN)

The ClearIP sign/verify routes are included but **commented out** in the template. To enable:

1. Edit `opensips.cfg.template`
2. Uncomment `route(CLEARIP_SIGN)` in the `TO_WAN` route
3. Uncomment `route(CLEARIP_VERIFY)` in the `TO_LAN` route
4. Adjust the API payload to match your ClearIP account settings
5. Rebuild: `docker compose up -d --build`

The original TransNexus config is saved inside the container at `/etc/opensips/opensips.cfg.transnexus` for reference.

## TLS Certificates

Self-signed certs are generated automatically on first run. To use your own:

```bash
docker run -d --network host \
  -e INTERNAL_IP=10.0.1.100 \
  -e EXTERNAL_IP=203.0.113.50 \
  -v /path/to/certs:/etc/opensips/tls:ro \
  opensips-clearip
```

Volume must contain `ckey.pem` and `cert.pem`.

## Customization

To modify the routing logic, edit `opensips.cfg.template`. Key areas you'll want to configure for production:

- **TO_WAN route** — Set `$du` to your SIP trunk provider's IP
- **TO_LAN route** — Set `$du` to your PBX IP address
- **ClearIP routes** — Uncomment and adjust API payloads

After changes, rebuild with `docker compose up -d --build`.

## Files

```
├── Dockerfile                  # Container build
├── docker-compose.yml          # Runtime config with env vars
├── entrypoint.sh               # IP validation + config generation + TLS + startup
├── opensips.cfg.template       # Dual-interface config (envsubst variables)
└── README.md
```
