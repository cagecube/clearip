# OpenSIPS ClearIP Docker — Ubuntu 24.04 Setup Guide

## Step 1: Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

## Step 2: Install Docker Engine

```bash
# Install prerequisites
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to the docker group (avoids needing sudo)
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker is running
docker --version
docker compose version
```

## Step 3: Configure the Firewall

```bash
# Allow SIP traffic
sudo ufw allow 5060/udp   # SIP UDP
sudo ufw allow 5060/tcp   # SIP TCP
sudo ufw allow 5061/tcp   # SIP TLS

# Verify
sudo ufw status
```

## Step 4: Clone the Repo

```bash
cd /opt
sudo git clone https://github.com/cagecube/clearip.git
sudo chown -R $USER:$USER /opt/clearip
cd /opt/clearip
```

## Step 5: Identify Your Network Interfaces

```bash
# Find your LAN and WAN IPs
ip -4 addr show

# Example output — look for your two interfaces:
#   eth0 (LAN):  10.0.1.100/24
#   eth1 (WAN):  203.0.113.50/24
```

## Step 6: Configure Environment Variables

```bash
cd /opt/clearip

# Edit docker-compose.yml with your actual IPs
nano docker-compose.yml
```

Update these two lines with your real IPs:
```yaml
- INTERNAL_IP=10.0.1.100       # <-- Your LAN IP
- EXTERNAL_IP=203.0.113.50     # <-- Your WAN IP
```

## Step 7: Build and Start the Container

```bash
cd /opt/clearip
docker compose up -d --build
```

## Step 8: Verify It's Running

```bash
# Check container status
docker ps

# Check startup logs
docker logs -f opensips-clearip

# You should see:
#   [entrypoint] Configuration:
#     Internal (LAN):  10.0.1.100:5060
#     External (WAN):  203.0.113.50:5060 (TLS: 5061)
#   [entrypoint] Generating self-signed TLS certificate...
#   [entrypoint] Starting OpenSIPS...
```

## Step 9: Verify SIP Ports Are Listening

```bash
# Check that OpenSIPS is bound to both IPs
sudo ss -tulnp | grep 506

# Expected output:
#   udp  UNCONN  0  0  10.0.1.100:5060    *  users:(("opensips",...))
#   udp  UNCONN  0  0  203.0.113.50:5060   *  users:(("opensips",...))
#   tcp  LISTEN  0  0  10.0.1.100:5060    *  users:(("opensips",...))
#   tcp  LISTEN  0  0  203.0.113.50:5060   *  users:(("opensips",...))
#   tcp  LISTEN  0  0  203.0.113.50:5061   *  users:(("opensips",...))
```

## Step 10: Test SIP Connectivity (Optional)

```bash
# Install SIP testing tool
sudo apt install -y sipsak

# Ping the LAN interface
sipsak -s sip:test@10.0.1.100:5060

# Ping the WAN interface
sipsak -s sip:test@203.0.113.50:5060
```

---

## Common Operations

### View live logs
```bash
docker logs -f opensips-clearip
```

### Restart the container
```bash
cd /opt/clearip
docker compose restart
```

### Rebuild after config changes
```bash
cd /opt/clearip
docker compose up -d --build
```

### Stop the container
```bash
cd /opt/clearip
docker compose down
```

### Update from GitHub
```bash
cd /opt/clearip
git pull origin main
docker compose up -d --build
```

---

## Production Checklist

- [ ] Set `INTERNAL_IP` and `EXTERNAL_IP` to your actual IPs
- [ ] Edit `opensips.cfg.template` — set trunk IP in `TO_WAN` route
- [ ] Edit `opensips.cfg.template` — set PBX IP in `TO_LAN` route
- [ ] Uncomment ClearIP routes if using STIR/SHAKEN
- [ ] Replace self-signed TLS cert with a real one (mount via volume)
- [ ] Set `TLS_CN` to your actual hostname/FQDN
- [ ] Configure firewall rules for your specific network
- [ ] Set up log rotation for Docker logs
