# OpenSIPS 3.4 Docker — Dual-Interface SIP Proxy for TransNexus ClearIP
# LAN (PBX/phones) <-> OpenSIPS <-> WAN (SIP trunks)

FROM debian:bookworm-slim

LABEL maintainer="contractor24x7"
LABEL description="OpenSIPS 3.4 dual-interface SIP proxy with TLS for TransNexus ClearIP"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies + envsubst (gettext-base)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gettext-base \
    gnupg \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Add OpenSIPS 3.4 repo for Debian Bookworm
RUN curl -fsSL https://apt.opensips.org/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/opensips-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/opensips-archive-keyring.gpg] https://apt.opensips.org bookworm 3.4-releases" \
    > /etc/apt/sources.list.d/opensips.list

# Install OpenSIPS with TLS + NAT + REST modules
RUN apt-get update && apt-get install -y --no-install-recommends \
    opensips \
    opensips-tls-module \
    opensips-tls-openssl-module \
    opensips-tlsmgm-module \
    opensips-nathelper-module \
    opensips-restclient-module \
    && rm -rf /var/lib/apt/lists/*

# Save the original TransNexus config as reference
RUN curl -fsSL https://files.transnexus.com/clearip/proxy/inline/opensips.cfg \
    > /etc/opensips/opensips.cfg.transnexus

# Copy our dual-interface config template and entrypoint
COPY opensips.cfg.template /etc/opensips/opensips.cfg.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create TLS directory
RUN mkdir -p /etc/opensips/tls

# Expose SIP ports (both interfaces)
EXPOSE 5060/udp
EXPOSE 5060/tcp
EXPOSE 5061/tcp

# ---------------------------------------------------------------------------
# Environment defaults — override at runtime
# ---------------------------------------------------------------------------
# REQUIRED (entrypoint will error if missing):
#   INTERNAL_IP    — LAN-facing IP (PBX/phones side)
#   EXTERNAL_IP    — WAN-facing IP (SIP trunk side)
#
# OPTIONAL:
ENV SHM_MEMORY=1024
ENV PKG_MEMORY=4
ENV TLS_CN=localhost
ENV INTERNAL_PORT=5060
ENV EXTERNAL_PORT=5060
ENV EXTERNAL_TLS_PORT=5061
ENV CLEARIP_URL=https://api.clearip.com

ENTRYPOINT ["/entrypoint.sh"]
