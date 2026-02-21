#!/usr/bin/env bash
set -euo pipefail

# Samsung TV Wake-on-LAN Script
# Wakes TV from standby using magic packet

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$SKILL_DIR/.venv"
CONFIG_DIR="$HOME/.config/samsung-tv"

# TV Configuration
TV_MAC="94:e6:ba:79:2a:32"
TV_IP="192.168.0.102"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}" >&2; }

# Activate venv
if [[ -f "$VENV_DIR/bin/activate" ]]; then
    source "$VENV_DIR/bin/activate"
else
    log_error "Virtual environment not found. Run setup first."
    exit 1
fi

echo "📺 Waking Samsung TV..."
echo "   MAC: $TV_MAC"
echo "   IP:  $TV_IP"
echo ""

# Send Wake-on-LAN magic packet
python3 << EOF
from wakeonlan import send_magic_packet
import time

mac = "$TV_MAC"
print(f"Sending magic packet to {mac}...")

# Send multiple times for reliability
for i in range(3):
    send_magic_packet(mac)
    time.sleep(0.5)

print("Magic packets sent!")
EOF

# Wait and check if TV is responding
echo ""
echo "Waiting for TV to wake up..."
sleep 3

if ping -c 1 -W 2 "$TV_IP" &>/dev/null; then
    log_info "TV is responding!"
else
    log_warn "TV not responding yet (may take a few more seconds)"
fi

echo ""
log_info "Wake command sent. TV should power on shortly."
