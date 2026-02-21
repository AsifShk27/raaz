#!/usr/bin/env bash
set -euo pipefail

# Samsung TV Control Script
# Supports SmartThings API (recommended) and local WebSocket

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$SKILL_DIR/.venv"
CONFIG_DIR="$HOME/.config/samsung-tv"

# TV Configuration
TV_IP="192.168.0.102"
TV_MAC="94:e6:ba:79:2a:32"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}" >&2; }
log_cmd() { echo -e "${CYAN}→ $1${NC}"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  power [on|off]     Power control (on uses Wake-on-LAN)
  volume <up|down|N> Volume control (N = 0-100)
  mute               Toggle mute
  app <name>         Launch app (netflix, youtube, prime, disney, etc.)
  apps               List installed apps
  input <source>     Switch input (hdmi1, hdmi2, tv)
  key <KEY>          Send remote key (HOME, BACK, ENTER, UP, DOWN, etc.)
  status             Check TV status

Examples:
  $(basename "$0") power on
  $(basename "$0") volume 30
  $(basename "$0") app netflix
  $(basename "$0") key HOME

EOF
    exit 2
}

# Activate venv
activate_venv() {
    if [[ -f "$VENV_DIR/bin/activate" ]]; then
        source "$VENV_DIR/bin/activate"
    else
        log_error "Virtual environment not found at $VENV_DIR"
        log_error "Run: python3 -m venv $VENV_DIR && $VENV_DIR/bin/pip install samsungtvws wakeonlan requests"
        exit 1
    fi
}

# Check if SmartThings is configured
has_smartthings() {
    [[ -f "$CONFIG_DIR/smartthings_token" ]] && [[ -f "$CONFIG_DIR/device_id" ]]
}

# SmartThings API call
smartthings_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local token
    token=$(cat "$CONFIG_DIR/smartthings_token")
    local device_id
    device_id=$(cat "$CONFIG_DIR/device_id")

    local url="https://api.smartthings.com/v1/devices/$device_id/$endpoint"

    local response
    if [[ -n "$data" ]]; then
        response=$(curl -s -X "$method" "$url" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -s -X "$method" "$url" \
            -H "Authorization: Bearer $token" 2>/dev/null)
    fi
    # Only output for GET requests or if there's an error
    if [[ "$method" == "GET" ]] || echo "$response" | grep -q '"error"'; then
        echo "$response"
    fi
}

# Send command via SmartThings
smartthings_command() {
    local capability="$1"
    local command="$2"
    local args="${3:-[]}"

    local data="{\"commands\":[{\"component\":\"main\",\"capability\":\"$capability\",\"command\":\"$command\",\"arguments\":$args}]}"
    smartthings_api "POST" "commands" "$data"
}

# Wake TV
do_wake() {
    log_cmd "Waking TV via Wake-on-LAN..."
    "$SCRIPT_DIR/wake.sh"
}

# Power control
do_power() {
    local action="${1:-toggle}"

    case "$action" in
        on)
            do_wake
            ;;
        off)
            if has_smartthings; then
                log_cmd "Powering off via SmartThings..."
                smartthings_command "switch" "off"
                log_info "Power off command sent"
            else
                log_cmd "Powering off via WebSocket..."
                python3 << EOF
from samsungtvws import SamsungTVWS
tv = SamsungTVWS(host='$TV_IP', port=8001, name='Clawdbot', timeout=5)
tv.send_key('KEY_POWER')
print("Power key sent")
EOF
            fi
            ;;
        *)
            # Toggle - try to detect state first
            if has_smartthings; then
                log_cmd "Toggling power via SmartThings..."
                local status
                status=$(smartthings_api "GET" "status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('components',{}).get('main',{}).get('switch',{}).get('switch',{}).get('value','unknown'))" 2>/dev/null || echo "unknown")
                if [[ "$status" == "on" ]]; then
                    smartthings_command "switch" "off"
                    log_info "TV powered off"
                else
                    do_wake
                fi
            else
                do_wake
            fi
            ;;
    esac
}

# Volume control
do_volume() {
    local action="$1"

    case "$action" in
        up)
            if has_smartthings; then
                smartthings_command "audioVolume" "volumeUp"
            else
                python3 -c "from samsungtvws import SamsungTVWS; SamsungTVWS(host='$TV_IP',port=8001,name='Clawdbot',timeout=5).send_key('KEY_VOLUP')"
            fi
            log_info "Volume up"
            ;;
        down)
            if has_smartthings; then
                smartthings_command "audioVolume" "volumeDown"
            else
                python3 -c "from samsungtvws import SamsungTVWS; SamsungTVWS(host='$TV_IP',port=8001,name='Clawdbot',timeout=5).send_key('KEY_VOLDOWN')"
            fi
            log_info "Volume down"
            ;;
        [0-9]|[0-9][0-9]|100)
            if has_smartthings; then
                smartthings_command "audioVolume" "setVolume" "[$action]"
                log_info "Volume set to $action"
            else
                log_error "Setting specific volume requires SmartThings API"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid volume command: $action"
            echo "Usage: volume <up|down|0-100>"
            exit 1
            ;;
    esac
}

# Mute toggle
do_mute() {
    if has_smartthings; then
        # Get current mute status and toggle
        local muted
        muted=$(smartthings_api "GET" "status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('components',{}).get('main',{}).get('audioMute',{}).get('mute',{}).get('value','unmuted'))" 2>/dev/null || echo "unmuted")
        if [[ "$muted" == "muted" ]]; then
            smartthings_command "audioMute" "unmute"
            log_info "Unmuted"
        else
            smartthings_command "audioMute" "mute"
            log_info "Muted"
        fi
    else
        python3 -c "from samsungtvws import SamsungTVWS; SamsungTVWS(host='$TV_IP',port=8001,name='Clawdbot',timeout=5).send_key('KEY_MUTE')"
        log_info "Mute toggled"
    fi
}

# Launch app
do_app() {
    local app_name="$1"

    # Common app IDs
    declare -A apps=(
        ["netflix"]="3201907018807"
        ["youtube"]="111299001912"
        ["prime"]="3201910019365"
        ["amazon"]="3201910019365"
        ["disney"]="3201901017640"
        ["disneyplus"]="3201901017640"
        ["apple"]="3201807016597"
        ["appletv"]="3201807016597"
        ["spotify"]="3201606009684"
        ["plex"]="3201512006963"
        ["hulu"]="3201601007625"
        ["hbo"]="3201601007230"
        ["paramount"]="3201512006785"
    )

    local app_id="${apps[$app_name]:-$app_name}"

    if has_smartthings; then
        log_cmd "Launching $app_name via SmartThings..."
        smartthings_command "mediaPlayback" "play"
        # SmartThings app launch is limited, try direct
    fi

    # Try local WebSocket for app launch
    log_cmd "Launching app: $app_name (ID: $app_id)..."
    python3 << EOF
from samsungtvws import SamsungTVWS
try:
    tv = SamsungTVWS(host='$TV_IP', port=8001, name='Clawdbot', timeout=10)
    tv.run_app('$app_id')
    print("App launch command sent")
except Exception as e:
    print(f"Error: {e}")
    print("Try using SmartThings app on your phone to launch the app")
EOF
}

# List apps
do_apps() {
    log_cmd "Getting installed apps..."
    python3 << EOF
from samsungtvws import SamsungTVWS
import json
try:
    tv = SamsungTVWS(host='$TV_IP', port=8001, name='Clawdbot', timeout=10)
    apps = tv.app_list()
    print(f"Found {len(apps)} apps:\n")
    for app in sorted(apps, key=lambda x: x.get('name', '')):
        print(f"  {app.get('name', 'Unknown'):30} {app.get('appId', 'N/A')}")
except Exception as e:
    print(f"Error getting app list: {e}")
    print("\nCommon apps:")
    print("  Netflix:     3201907018807")
    print("  YouTube:     111299001912")
    print("  Prime Video: 3201910019365")
    print("  Disney+:     3201901017640")
EOF
}

# Input switching
do_input() {
    local source="$1"

    declare -A inputs=(
        ["hdmi1"]="KEY_HDMI1"
        ["hdmi2"]="KEY_HDMI2"
        ["hdmi3"]="KEY_HDMI3"
        ["hdmi4"]="KEY_HDMI4"
        ["tv"]="KEY_TV"
        ["usb"]="KEY_USB"
    )

    local key="${inputs[$source]:-}"

    if [[ -z "$key" ]]; then
        log_error "Unknown input: $source"
        echo "Valid inputs: hdmi1, hdmi2, hdmi3, hdmi4, tv, usb"
        exit 1
    fi

    if has_smartthings; then
        log_cmd "Switching to $source via SmartThings..."
        smartthings_command "mediaInputSource" "setInputSource" "[\"$source\"]"
    else
        python3 -c "from samsungtvws import SamsungTVWS; SamsungTVWS(host='$TV_IP',port=8001,name='Clawdbot',timeout=5).send_key('$key')"
    fi
    log_info "Switched to $source"
}

# Send key
do_key() {
    local key="$1"

    # Normalize key name
    key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
    [[ "$key" != KEY_* ]] && key="KEY_$key"

    log_cmd "Sending key: $key"

    if has_smartthings && [[ "$key" == "KEY_HOME" ]]; then
        smartthings_command "mediaPlayback" "stop"
    fi

    python3 << EOF
from samsungtvws import SamsungTVWS
try:
    tv = SamsungTVWS(host='$TV_IP', port=8001, name='Clawdbot', timeout=5)
    tv.send_key('$key')
    print("Key sent successfully")
except Exception as e:
    print(f"Error: {e}")
EOF
}

# Status check
do_status() {
    echo "📺 Samsung TV Status"
    echo "===================="
    echo ""

    # Check if TV is reachable
    if ping -c 1 -W 2 "$TV_IP" &>/dev/null; then
        log_info "TV is reachable at $TV_IP"
    else
        log_warn "TV not responding to ping (may be in deep standby)"
    fi

    # Check REST API
    local api_response
    api_response=$(curl -s --connect-timeout 3 "http://$TV_IP:8001/api/v2/" 2>/dev/null || echo "")

    if [[ -n "$api_response" ]]; then
        echo ""
        echo "$api_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    device = data.get('device', {})
    print(f\"Model:      {device.get('modelName', 'Unknown')}\")
    name = device.get('name', 'Unknown').replace('&quot;', '\"')
    print(f\"Name:       {name}\")
    print(f\"Power:      {device.get('PowerState', 'Unknown')}\")
    print(f\"Resolution: {device.get('resolution', 'Unknown')}\")
    print(f\"OS:         {device.get('OS', 'Unknown')}\")
    print(f\"Network:    {device.get('networkType', 'Unknown')}\")
except Exception as e:
    print(f'Error parsing TV info: {e}')
"
    else
        log_warn "Could not get TV info (TV may be off)"
    fi

    # Check SmartThings config
    echo ""
    if has_smartthings; then
        log_info "SmartThings API configured"
    else
        log_warn "SmartThings API not configured"
        echo "  To configure: see skill documentation"
    fi
}

# Main
main() {
    [[ $# -eq 0 ]] && usage

    activate_venv

    local cmd="$1"
    shift

    case "$cmd" in
        power)
            do_power "${1:-toggle}"
            ;;
        volume|vol)
            [[ $# -eq 0 ]] && { log_error "Volume requires argument"; exit 1; }
            do_volume "$1"
            ;;
        mute)
            do_mute
            ;;
        app)
            [[ $# -eq 0 ]] && { log_error "App name required"; exit 1; }
            do_app "$1"
            ;;
        apps|list)
            do_apps
            ;;
        input|source)
            [[ $# -eq 0 ]] && { log_error "Input source required"; exit 1; }
            do_input "$1"
            ;;
        key)
            [[ $# -eq 0 ]] && { log_error "Key name required"; exit 1; }
            do_key "$1"
            ;;
        status)
            do_status
            ;;
        wake)
            do_wake
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            ;;
    esac
}

main "$@"
