#!/bin/bash
###############################################################################
# OpenSIPS ClearIP Docker — Ubuntu 24.04 One-Line Setup
# Usage: sudo bash setup.sh
###############################################################################
set -e

# ── Colors ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── Must be root ──
if [ "$EUID" -ne 0 ]; then
    error "Please run as root:  sudo bash setup.sh"
fi

INSTALL_DIR="/opt/clearip"
REPO_URL="https://github.com/cagecube/clearip.git"
REAL_USER="${SUDO_USER:-$USER}"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   OpenSIPS ClearIP Docker — Ubuntu 24.04 Setup           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

###############################################################################
# Step 1: System Update
###############################################################################
info "Updating system packages..."
apt update -y && apt upgrade -y

###############################################################################
# Step 2: Install Docker (skip if already installed)
###############################################################################
if command -v docker &> /dev/null; then
    info "Docker already installed: $(docker --version)"
else
    info "Installing Docker Engine..."
    apt install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add the real user to docker group
    usermod -aG docker "$REAL_USER"
    info "Docker installed: $(docker --version)"
fi

# Ensure Docker is running
systemctl enable docker
systemctl start docker

###############################################################################
# Step 3: Install helper tools
###############################################################################
info "Installing helper tools..."
apt install -y git sipsak ufw -y

###############################################################################
# Step 4: Configure Firewall
###############################################################################
info "Configuring firewall..."
ufw allow 22/tcp      >/dev/null 2>&1   # SSH (don't lock yourself out)
ufw allow 5060/udp    >/dev/null 2>&1   # SIP UDP
ufw allow 5060/tcp    >/dev/null 2>&1   # SIP TCP
ufw allow 5061/tcp    >/dev/null 2>&1   # SIP TLS
ufw --force enable    >/dev/null 2>&1
info "Firewall configured (SSH + SIP ports open)"

###############################################################################
# Step 5: Clone the repo
###############################################################################
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repo already exists at $INSTALL_DIR — pulling latest..."
    cd "$INSTALL_DIR"
    git pull origin main
else
    info "Cloning repo to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi
chown -R "$REAL_USER":"$REAL_USER" "$INSTALL_DIR"

###############################################################################
# Step 6: Detect network interfaces and prompt for IPs
###############################################################################
echo ""
echo "─── Available Network Interfaces ───────────────────────────"
ip -4 -o addr show | awk '{printf "  %-12s %s\n", $2, $4}' | grep -v "127.0.0.1"
echo "────────────────────────────────────────────────────────────"
echo ""

# Try to auto-detect private (LAN) and public (WAN) IPs
AUTO_LAN=$(ip -4 -o addr show | awk '{print $4}' | sed 's/\/.*$//' | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | head -1)
AUTO_WAN=$(ip -4 -o addr show | awk '{print $4}' | sed 's/\/.*$//' | grep -v -E '^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' | head -1)

# Prompt for LAN IP
if [ -n "$AUTO_LAN" ]; then
    read -rp "$(echo -e "${YELLOW}[?]${NC}") Internal/LAN IP [$AUTO_LAN]: " INTERNAL_IP
    INTERNAL_IP="${INTERNAL_IP:-$AUTO_LAN}"
else
    read -rp "$(echo -e "${YELLOW}[?]${NC}") Internal/LAN IP (PBX/phones side): " INTERNAL_IP
fi

# Prompt for WAN IP
if [ -n "$AUTO_WAN" ]; then
    read -rp "$(echo -e "${YELLOW}[?]${NC}") External/WAN IP [$AUTO_WAN]: " EXTERNAL_IP
    EXTERNAL_IP="${EXTERNAL_IP:-$AUTO_WAN}"
else
    read -rp "$(echo -e "${YELLOW}[?]${NC}") External/WAN IP (SIP trunk side): " EXTERNAL_IP
fi

# Validate IPs
if [ -z "$INTERNAL_IP" ] || [ -z "$EXTERNAL_IP" ]; then
    error "Both INTERNAL_IP and EXTERNAL_IP are required."
fi

info "LAN IP:  $INTERNAL_IP"
info "WAN IP:  $EXTERNAL_IP"

###############################################################################
# Step 7: Optional — Trunk and PBX IPs
###############################################################################
echo ""
read -rp "$(echo -e "${YELLOW}[?]${NC}") PBX IP address (leave blank to configure later): " PBX_IP
read -rp "$(echo -e "${YELLOW}[?]${NC}") SIP Trunk IP address (leave blank to configure later): " TRUNK_IP

###############################################################################
# Step 8: Write docker-compose.yml with actual IPs
###############################################################################
info "Writing docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
version: "3.8"

services:
  opensips:
    build: .
    container_name: opensips-clearip
    restart: unless-stopped
    network_mode: host
    environment:
      - INTERNAL_IP=${INTERNAL_IP}
      - EXTERNAL_IP=${EXTERNAL_IP}
      - INTERNAL_PORT=5060
      - EXTERNAL_PORT=5060
      - EXTERNAL_TLS_PORT=5061
      - SHM_MEMORY=1024
      - PKG_MEMORY=4
      - TLS_CN=${EXTERNAL_IP}
      - CLEARIP_URL=https://api.clearip.com
    volumes:
      - tls-certs:/etc/opensips/tls

volumes:
  tls-certs:
EOF

###############################################################################
# Step 9: Build and start
###############################################################################
info "Building and starting OpenSIPS container..."
cd "$INSTALL_DIR"
docker compose up -d --build

###############################################################################
# Step 10: Health check
###############################################################################
info "Waiting for container to start..."
sleep 3

if docker ps | grep -q opensips-clearip; then
    info "Container is running!"
else
    error "Container failed to start. Check logs: docker logs opensips-clearip"
fi

echo ""
echo "─── Listening Ports ────────────────────────────────────────"
ss -tulnp | grep 506 || warn "No SIP ports detected yet — container may still be starting"
echo "────────────────────────────────────────────────────────────"

###############################################################################
# Summary
###############################################################################
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Setup Complete!                                         ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║                                                           ║"
echo "║   LAN (PBX/phones):  ${INTERNAL_IP}:5060                 "
echo "║   WAN (SIP trunk):   ${EXTERNAL_IP}:5060 / :5061 (TLS)  "
echo "║                                                           ║"
echo "║   Install dir:       ${INSTALL_DIR}                      "
echo "║                                                           ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║   Useful Commands:                                        ║"
echo "║   ─────────────────────────────────────────────────────   ║"
echo "║   Logs:      docker logs -f opensips-clearip              ║"
echo "║   Restart:   cd ${INSTALL_DIR} && docker compose restart  "
echo "║   Rebuild:   cd ${INSTALL_DIR} && docker compose up -d --build"
echo "║   Stop:      cd ${INSTALL_DIR} && docker compose down     "
echo "║   Test LAN:  sipsak -s sip:test@${INTERNAL_IP}:5060      "
echo "║   Test WAN:  sipsak -s sip:test@${EXTERNAL_IP}:5060      "
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ -n "$PBX_IP" ] || [ -n "$TRUNK_IP" ]; then
    warn "Remember to edit opensips.cfg.template with your PBX/Trunk IPs:"
    [ -n "$PBX_IP" ]   && echo "       PBX IP:   $PBX_IP   → set \$du in TO_LAN route"
    [ -n "$TRUNK_IP" ] && echo "       Trunk IP: $TRUNK_IP  → set \$du in TO_WAN route"
    echo "       Then rebuild: cd $INSTALL_DIR && docker compose up -d --build"
    echo ""
else
    warn "Next step: Edit opensips.cfg.template to set your PBX and Trunk IPs"
    warn "Then rebuild: cd $INSTALL_DIR && docker compose up -d --build"
    echo ""
fi

info "Done! Don't forget to rotate your GitHub token if you shared it."
