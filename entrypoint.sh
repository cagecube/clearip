#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
if [ -z "$INTERNAL_IP" ]; then
    echo "[entrypoint] ERROR: INTERNAL_IP is required (LAN-facing IP for PBX/phones)"
    echo "[entrypoint] Example: -e INTERNAL_IP=10.0.1.100"
    exit 1
fi

if [ -z "$EXTERNAL_IP" ]; then
    echo "[entrypoint] ERROR: EXTERNAL_IP is required (WAN-facing IP for SIP trunks)"
    echo "[entrypoint] Example: -e EXTERNAL_IP=203.0.113.50"
    exit 1
fi

echo "[entrypoint] Configuration:"
echo "  Internal (LAN):  ${INTERNAL_IP}:${INTERNAL_PORT:-5060}"
echo "  External (WAN):  ${EXTERNAL_IP}:${EXTERNAL_PORT:-5060} (TLS: ${EXTERNAL_TLS_PORT:-5061})"
echo "  Memory:          SHM=${SHM_MEMORY}M  PKG=${PKG_MEMORY}M"
echo "  ClearIP URL:     ${CLEARIP_URL}"

# ---------------------------------------------------------------------------
# Generate opensips.cfg from template using envsubst
# ---------------------------------------------------------------------------
echo "[entrypoint] Generating opensips.cfg from template..."
envsubst '${INTERNAL_IP} ${INTERNAL_PORT} ${EXTERNAL_IP} ${EXTERNAL_PORT} ${EXTERNAL_TLS_PORT} ${CLEARIP_URL}' \
    < /etc/opensips/opensips.cfg.template \
    > /etc/opensips/opensips.cfg

# ---------------------------------------------------------------------------
# Generate self-signed TLS certificate if none exists
# ---------------------------------------------------------------------------
TLS_DIR="/etc/opensips/tls"
TLS_KEY="${TLS_DIR}/ckey.pem"
TLS_CERT="${TLS_DIR}/cert.pem"

if [ ! -f "$TLS_KEY" ] || [ ! -f "$TLS_CERT" ]; then
    echo "[entrypoint] Generating self-signed TLS certificate (CN=${TLS_CN:-localhost})..."
    openssl req -x509 -nodes \
        -newkey rsa:2048 -sha256 \
        -keyout "$TLS_KEY" \
        -out "$TLS_CERT" \
        -subj "/CN=${TLS_CN:-localhost}" \
        -days 3653
    echo "[entrypoint] TLS certificate created."
else
    echo "[entrypoint] Using existing TLS certificate."
fi

# Ensure opensips user owns config files
chown -R opensips:opensips /etc/opensips

# ---------------------------------------------------------------------------
# Start OpenSIPS in foreground
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting OpenSIPS..."
exec opensips -F \
    -m "$SHM_MEMORY" \
    -M "$PKG_MEMORY" \
    -f /etc/opensips/opensips.cfg
