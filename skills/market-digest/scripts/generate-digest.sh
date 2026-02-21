#!/bin/bash

# Daily Market Digest Generator
# Uses: Google Maps API (traffic), blogwatcher (RSS), Open-Meteo (weather)
#
# NOTE: This uses Google Maps Distance Matrix API (Cloud Platform)
# NOT gog CLI (which is for Workspace APIs like Gmail/Calendar/Drive)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HN_DIGEST_SCRIPT="${SCRIPT_DIR}/hn-digest.sh"
TECH_STORY_COUNT="${MARKET_DIGEST_TECH_COUNT:-3}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default behavior (daily mode): mark articles as read after digest generation.
# On-demand callers can preserve read state with:
#   --preserve-read-state (or --no-mark-read)
MARK_READ_MODE="${MARKET_DIGEST_MARK_READ:-1}"
for arg in "$@"; do
  case "$arg" in
    --preserve-read-state|--no-mark-read)
      MARK_READ_MODE="0"
      ;;
    --mark-read)
      MARK_READ_MODE="1"
      ;;
  esac
done

echo "📈 Generating Daily Market Digest..."

# 1. WEATHER - Open-Meteo (free, no API key)
echo -e "${YELLOW}Fetching weather...${NC}"
WEATHER_JSON=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=12.9716&longitude=77.5946&current_weather=true")

# Use jq for reliable JSON parsing
if command -v jq &> /dev/null; then
  TEMP=$(echo "$WEATHER_JSON" | jq -r '.current_weather.temperature // empty')
  WEATHER_CODE=$(echo "$WEATHER_JSON" | jq -r '.current_weather.weathercode // empty')
else
  # Fallback to grep if jq not available
  TEMP=$(echo "$WEATHER_JSON" | grep -o '"temperature":[^,]*' | cut -d':' -f2)
  WEATHER_CODE=$(echo "$WEATHER_JSON" | grep -o '"weathercode":[^,]*' | cut -d':' -f2)
fi

# Weather code mapping (WMO codes)
case $WEATHER_CODE in
  0) CONDITIONS="Clear sky ☀️" ;;
  1) CONDITIONS="Mainly clear 🌤️" ;;
  2) CONDITIONS="Partly cloudy ⛅" ;;
  3) CONDITIONS="Overcast ☁️" ;;
  45|48) CONDITIONS="Fog 🌫️" ;;
  51|53|55) CONDITIONS="Drizzle 🌧️" ;;
  56|57) CONDITIONS="Freezing drizzle 🌧️" ;;
  61|63|65) CONDITIONS="Rain 🌧️" ;;
  66|67) CONDITIONS="Freezing rain 🌧️" ;;
  71|73|75) CONDITIONS="Snow ❄️" ;;
  77) CONDITIONS="Snow grains ❄️" ;;
  80|81|82) CONDITIONS="Showers 🌦️" ;;
  85|86) CONDITIONS="Snow showers ❄️" ;;
  95) CONDITIONS="Thunderstorm ⛈️" ;;
  96|99) CONDITIONS="Thunderstorm with hail ⛈️" ;;
  *) CONDITIONS="Unknown" ;;
esac

if [ -n "$TEMP" ]; then
  WEATHER_LINE="🌡️ Bangalore: ${TEMP}°C, ${CONDITIONS}"
else
  WEATHER_LINE="🌡️ Bangalore: Weather data unavailable"
fi
echo "$WEATHER_LINE"

# 2. TRAFFIC - Using Google Maps Distance Matrix API
# NOTE: This is a separate Google Cloud Platform API, NOT part of gog (Workspace APIs)
echo -e "${YELLOW}Fetching traffic data...${NC}"

# Get Google Maps API key from credentials file
MAPS_API_KEY=$(cat ~/.openclaw/credentials/google-maps.json 2>/dev/null | jq -r '.apiKey // empty')

if [ -z "$MAPS_API_KEY" ] || [ "$MAPS_API_KEY" = "null" ]; then
  echo -e "${RED}Error: Google Maps API key not found at ~/.openclaw/credentials/google-maps.json${NC}"
  echo "To fix: Create the file with: {\"apiKey\": \"YOUR_GOOGLE_MAPS_API_KEY\"}"
  TRAFFIC_LINE="🚗 Traffic: Not available (API key missing)"
else
  # Google Maps Distance Matrix API call
  TRAFFIC_JSON=$(curl -s "https://maps.googleapis.com/maps/api/distancematrix/json?origins=RVS%20Shastri%20Residency%2C%20Bohra%20Layout%2C%20Gottigere%2C%20Bangalore%20560083&destinations=ECOSPACE%20BUSINESS%20PARK%2C%20Piritech%20Park%20(SEZ)%2C%20Phase%201%2C%20Adarsh%20Palm%20Retreat%2C%20Bellandur%2C%20Bangalore%20560103&departure_time=now&traffic_model=best_guess&key=$MAPS_API_KEY")

  # Check API status
  API_STATUS=$(echo "$TRAFFIC_JSON" | jq -r '.status // empty')

  if [ "$API_STATUS" = "OK" ]; then
    # Use jq to properly parse nested JSON (handles spaces in Google's response)
    ELEMENT_STATUS=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].status // empty')

    if [ "$ELEMENT_STATUS" = "OK" ]; then
      DISTANCE=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].distance.text // empty')
      DURATION=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].duration.text // empty')
      DURATION_IN_TRAFFIC=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].duration_in_traffic.text // empty')

      if [ -n "$DISTANCE" ] && [ -n "$DURATION_IN_TRAFFIC" ]; then
        # Add traffic indicator
        DURATION_NORMAL=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].duration.value // 0')
        DURATION_TRAFFIC=$(echo "$TRAFFIC_JSON" | jq -r '.rows[0].elements[0].duration_in_traffic.value // 0')

        if [ "$DURATION_TRAFFIC" -gt 0 ] && [ "$DURATION_NORMAL" -gt 0 ]; then
          TRAFFIC_RATIO=$((DURATION_TRAFFIC * 100 / DURATION_NORMAL))
          if [ "$TRAFFIC_RATIO" -gt 130 ]; then
            TRAFFIC_INDICATOR="🔴 Heavy"
          elif [ "$TRAFFIC_RATIO" -gt 115 ]; then
            TRAFFIC_INDICATOR="🟡 Moderate"
          else
            TRAFFIC_INDICATOR="🟢 Light"
          fi
          TRAFFIC_LINE="🚗 Home → Office: ${DISTANCE} | ${DURATION_IN_TRAFFIC} (${TRAFFIC_INDICATOR} traffic)"
        else
          TRAFFIC_LINE="🚗 Home → Office: ${DISTANCE} | ${DURATION_IN_TRAFFIC}"
        fi
      else
        TRAFFIC_LINE="🚗 Home → Office: Route available, traffic data missing"
      fi
    else
      TRAFFIC_LINE="🚗 Home → Office: Route not found (${ELEMENT_STATUS})"
    fi
  else
    ERROR_MSG=$(echo "$TRAFFIC_JSON" | jq -r '.error_message // empty')
    if [ -n "$ERROR_MSG" ]; then
      echo -e "${RED}API Error: $ERROR_MSG${NC}"
    fi
    TRAFFIC_LINE="🚗 Traffic: API error (${API_STATUS})"
  fi

  echo "$TRAFFIC_LINE"
fi

# 3. MARKET NEWS - Using blogwatcher
echo -e "${YELLOW}Fetching market news from blogwatcher...${NC}"
if ! blogwatcher scan > /dev/null 2>&1; then
  echo -e "${RED}Warning: blogwatcher scan failed; using current cached article list.${NC}"
fi

extract_article_rows() {
  awk '
    BEGIN {
      count = 0
      title = ""
    }
    /^[[:space:]]*\[[0-9]+\][[:space:]]+\[[^]]+\][[:space:]]+/ {
      title = $0
      sub(/^[[:space:]]*\[[0-9]+\][[:space:]]+\[[^]]+\][[:space:]]+/, "", title)
      next
    }
    /^[[:space:]]*URL:[[:space:]]+/ {
      if (title != "" && count < 5) {
        url = $0
        sub(/^[[:space:]]*URL:[[:space:]]+/, "", url)
        printf "%s\t%s\n", title, url
        count++
        title = ""
      }
      if (count >= 5) {
        exit
      }
    }
  '
}

extract_tech_article_rows() {
  awk -v limit="${1:-3}" '
    BEGIN {
      count = 0
      title = ""
      is_tech = 0
    }
    /^[[:space:]]*\[[0-9]+\][[:space:]]+\[[^]]+\][[:space:]]+/ {
      title = $0
      sub(/^[[:space:]]*\[[0-9]+\][[:space:]]+\[[^]]+\][[:space:]]+/, "", title)
      t = tolower(title)
      is_tech = (
        t ~ /(^|[^a-z])(ai|artificial intelligence|technology|tech|software|hardware|semiconductor|chip|gpu|cloud|cyber|security|startup|data center|openai|anthropic|nvidia|alphabet|google|microsoft|apple|meta|tesla|amd|intel|tsmc)([^a-z]|$)/
      )
      next
    }
    /^[[:space:]]*URL:[[:space:]]+/ {
      if (title != "" && is_tech == 1 && count < limit) {
        url = $0
        sub(/^[[:space:]]*URL:[[:space:]]+/, "", url)
        printf "%s\t%s\n", title, url
        count++
      }
      title = ""
      is_tech = 0
      if (count >= limit) {
        exit
      }
    }
  '
}

# Parse top 5 articles from current multiline blogwatcher output:
#   [2257] [new] <title>
#      URL: <url>
ARTICLE_ROWS=$(blogwatcher articles | extract_article_rows)

# If there are no unread/parsable entries, fall back to latest overall list.
if [ -z "$ARTICLE_ROWS" ]; then
  ARTICLE_ROWS=$(blogwatcher articles --all | extract_article_rows)
fi

# 4. TECH NEWS - Prefer Hacker News digest, fall back to tech-filtered RSS
echo -e "${YELLOW}Fetching tech news...${NC}"
TECH_ROWS=""

if [ -x "$HN_DIGEST_SCRIPT" ]; then
  HN_RAW="$("$HN_DIGEST_SCRIPT" "$TECH_STORY_COUNT" tech 0 2>/dev/null || true)"
  if [ -n "$HN_RAW" ] && command -v jq > /dev/null 2>&1; then
    TECH_ROWS=$(echo "$HN_RAW" | jq -r '[.title // "", .url // ""] | @tsv' 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n "$TECH_STORY_COUNT")
  fi
fi

# Fallback for environments where HN digest is unavailable or empty.
if [ -z "$TECH_ROWS" ]; then
  TECH_ROWS=$(blogwatcher articles --all | extract_tech_article_rows "$TECH_STORY_COUNT")
fi

# Build the digest
DATE=$(date +%Y-%m-%d)
SNAPSHOT_IST=$(TZ=Asia/Kolkata date +"%b %d, %Y %I:%M %p IST")
OUTPUT="📊 Daily Market Digest - $(date +%b\ %d,\ %Y)\n\n"
OUTPUT+="🕒 News snapshot: ${SNAPSHOT_IST}\n"
OUTPUT+="(Latest available headlines from configured feeds at generation time)\n\n"
OUTPUT+="$WEATHER_LINE\n\n"
OUTPUT+="$TRAFFIC_LINE\n\n"
OUTPUT+="📈 Market News:\n"

# Add articles (format: Title — URL)
ARTICLE_COUNT=1
if [ -n "$ARTICLE_ROWS" ]; then
  while IFS=$'\t' read -r TITLE URL; do
    [ -z "$TITLE" ] && continue
    if [ -n "$URL" ]; then
      OUTPUT+="$ARTICLE_COUNT. $TITLE\n"
      OUTPUT+="   Link: $URL\n"
    else
      OUTPUT+="$ARTICLE_COUNT. $TITLE\n"
    fi
    ((ARTICLE_COUNT++))
  done <<< "$ARTICLE_ROWS"
else
  OUTPUT+="• No fresh RSS headlines available right now (blogwatcher returned no parsable articles).\n"
fi

# Add tech news section
OUTPUT+="\n💻 Tech News:\n"
TECH_COUNT=1
if [ -n "$TECH_ROWS" ]; then
  while IFS=$'\t' read -r TITLE URL; do
    [ -z "$TITLE" ] && continue
    if [ -n "$URL" ]; then
      OUTPUT+="$TECH_COUNT. $TITLE\n"
      OUTPUT+="   Link: $URL\n"
    else
      OUTPUT+="$TECH_COUNT. $TITLE\n"
    fi
    ((TECH_COUNT++))
  done <<< "$TECH_ROWS"
else
  OUTPUT+="• No fresh tech headlines available right now.\n"
fi

# Add "Things to watch"
OUTPUT+="\n🎯 Things to Watch Today:\n"
OUTPUT+="• Q3 earnings season momentum\n"
OUTPUT+="• RBI policy guidance cues\n"
OUTPUT+="• FII flow trends\n"

OUTPUT+="\nNot financial advice. 🐧"

# Output the digest
echo ""
echo "========================================="
echo -e "${GREEN}$OUTPUT${NC}"
echo "========================================="

# Write to temp file for sending
echo -e "$OUTPUT" > /tmp/market-digest-$(date +%Y-%m-%d).txt

# Mark articles as read for daily mode; preserve state for on-demand mode.
mark_read_normalized="$(echo "$MARK_READ_MODE" | tr '[:upper:]' '[:lower:]')"
if [[ "$mark_read_normalized" == "1" || "$mark_read_normalized" == "true" || "$mark_read_normalized" == "yes" ]]; then
  blogwatcher read-all -y > /dev/null 2>&1 || true
else
  echo "ℹ️ Preserving blogwatcher read state (on-demand mode)."
fi

echo ""
echo "✅ Digest generated successfully!"
echo "📁 Saved to: /tmp/market-digest-$(date +%Y-%m-%d).txt"
