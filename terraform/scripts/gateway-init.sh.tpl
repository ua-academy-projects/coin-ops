#!/bin/bash
# Primary multicloud gateway bootstrap (NAT + forwarding baseline).
set -euo pipefail

log() { echo "[gateway-init] $*"; }

log "Enabling IP forwarding..."
cat >/etc/sysctl.d/99-coinops-gateway.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

IFACE=$(ip route show default | awk '/default/ { print $5 }' | head -1)
log "Detected outbound interface: $IFACE"

iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
iptables -t nat -C POSTROUTING -s ${vpc_cidr} -o tailscale0 -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s ${vpc_cidr} -o tailscale0 -j MASQUERADE

iptables -C FORWARD -i "$IFACE" -o tailscale0 -s ${private_subnet_cidr} -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$IFACE" -o tailscale0 -s ${private_subnet_cidr} -j ACCEPT
iptables -C FORWARD -i tailscale0 -o "$IFACE" -d ${private_subnet_cidr} -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i tailscale0 -o "$IFACE" -d ${private_subnet_cidr} -j ACCEPT

iptables -C FORWARD -i "$IFACE" -o "$IFACE" -s ${private_subnet_cidr} -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$IFACE" -o "$IFACE" -s ${private_subnet_cidr} -j ACCEPT
iptables -C FORWARD -i "$IFACE" -o "$IFACE" -d ${private_subnet_cidr} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$IFACE" -o "$IFACE" -d ${private_subnet_cidr} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y iptables-persistent netfilter-persistent
  netfilter-persistent save
  systemctl enable netfilter-persistent
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y iptables-services
  service iptables save || true
  systemctl enable iptables || true
elif command -v yum >/dev/null 2>&1; then
  yum install -y iptables-services
  service iptables save || true
  systemctl enable iptables || true
else
  log "No supported package manager found; iptables persistence skipped."
fi

log "Gateway baseline setup complete."
