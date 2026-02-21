---
name: market-digest-now
description: Generate and send a financial markets digest on-demand (India + global). NO once-per-day guard - can be invoked anytime.
metadata: {"openclaw":{"emoji":"📊","requires":{"bins":["blogwatcher","jq","curl"]}}}
---

# market-digest-now

Generate a **financial markets** summary for Asif **on-demand**.

This is the on-demand version of `/market-digest` - it has **NO once-per-day guard** and can be invoked anytime.

## Execution command

Use the shared digest script path directly (strict allowlist compatible):

```bash
/home/shkas/projects/raaz/skills/market-digest/scripts/generate-digest.sh --preserve-read-state
```

Do not prefix with `bash`; execute the script path itself.

## Delivery Contract (Required)

After running the script, send the generated digest text verbatim from:

```bash
cat /tmp/market-digest-$(date +%Y-%m-%d).txt
```

Rules:
- Keep all raw `https://` links intact.
- Do not replace URLs with source labels (e.g. `Bloomberg`, `The Verge`).
- Do not paraphrase/rewrite headings or headlines.
- Preserve numbering and multi-line text exactly.

## Important Notes

- **Does NOT update** `market-digest-last.txt` (preserves the scheduled digest timing)
- **Does NOT affect** the 8am daily digest schedule
- Use this when you want a quick market update outside the scheduled time

## ⚠️ IMPORTANT: GOG vs Google Maps API

**GOG** (`gog` CLI) = Google **Workspace** APIs (Gmail, Calendar, Drive, Sheets, Docs)
**Google Maps API** = Google **Cloud Platform** service (requires API key, NOT OAuth)

**This skill does NOT use gog for traffic!** Traffic data comes from Google Maps Distance Matrix API using an API key stored at `~/.openclaw/credentials/google-maps.json`.

## Inputs
- Timezone: `Asia/Kolkata`
- Delivery surface: WhatsApp (main session)

## Sources

### 1. Weather (always include - FIRST)
Use the `weather` skill from ClawdHub:
```bash
curl -s "wttr.in/Bangalore?format=3"
# Output: Bangalore: ☀️ +19°C

# Or use weather skill script if available
weather Bangalore
```

Parse with jq:
- `.current_weather.temperature` - Temperature in °C
- `.current_weather.weathercode` - WMO weather code

WMO code to emoji+text mapping:
```
0 → ☀️ Clear sky
1 → 🌤️ Mainly clear
2 → ⛅ Partly cloudy
3 → ☁️ Overcast
45,48 → 🌫️ Fog
51-57 → 🌧️ Drizzle
61-67 → 🌧️ Rain
71-77 → ❄️ Snow
80-82 → 🌦️ Showers
95-99 → ⛈️ Thunderstorm
```

Example output: `🌡️ Bangalore: 24°C, Partly cloudy ⛅`

### 2. Traffic: Home → Office (always include - SECOND)

**API:** Google Maps Distance Matrix API (Cloud Platform, NOT gog Workspace)
**Credential:** `~/.openclaw/credentials/google-maps.json` containing `{"apiKey": "..."}`

```bash
API_KEY=$(jq -r '.apiKey' ~/.openclaw/credentials/google-maps.json)
TRAFFIC=$(curl -s "https://maps.googleapis.com/maps/api/distancematrix/json?\
origins=RVS%20Shastri%20Residency%2C%20Bohra%20Layout%2C%20Gottigere%2C%20Bangalore%20560083&\
destinations=ECOSPACE%20BUSINESS%20PARK%2C%20Bellandur%2C%20Bangalore%20560103&\
departure_time=now&traffic_model=best_guess&key=$API_KEY")

# Parse with jq
DISTANCE=$(echo "$TRAFFIC" | jq -r '.rows[0].elements[0].distance.text')
DURATION_TRAFFIC=$(echo "$TRAFFIC" | jq -r '.rows[0].elements[0].duration_in_traffic.text')
```

**Default Locations (with PIN codes):**
- **Home:** RVS Shastri Residency, Bohra Layout, Gottigere, Bangalore 560083
- **Office:** ECOSPACE BUSINESS PARK, Piritech Park (SEZ), Phase 1, Adarsh Palm Retreat, Bellandur, Bangalore 560103

**Traffic intensity indicator** (based on traffic/normal ratio):
- 🟢 Light traffic (< 15% delay)
- 🟡 Moderate traffic (15-30% delay)
- 🔴 Heavy traffic (> 30% delay)

Example output: `🚗 Home → Office: 26.6 km | 54 mins (🟡 Moderate traffic)`

### 3. RSS Market News (primary)
Use `blogwatcher`:
```bash
blogwatcher scan
blogwatcher articles  # prefer items from last ~24-36h
```

Tracked feeds (verified working):
- Bloomberg Markets
- Economic Times Markets
- Economic Times Economy
- Hindu Business Line
- Livemint Markets
- RBI Publications

### Web search (optional, for context)
Use the `browser` tool to quickly sanity-check "big picture" moves:
- US indices overnight move
- USD/INR, crude, gold
- Any major macro event (CPI, FOMC, RBI, budget headlines)

Keep web usage light: 3-6 quick queries.

### 4. Hacker News Tech Digest (NEW!)
Use the `hn-digest.sh` script for top tech stories:
```bash
./hn-digest.sh 5 tech 0  # 5 stories, tech topic, no offset
./hn-digest.sh 3 hacking 0  # 3 security-focused stories
```

HN Topics: `tech` (default), `hacking`, `health`, `life`

**Features:**
- Fetches from Hacker News Firebase API
- Boosts score for topic-matching keywords
- Excludes crypto/blockchain content
- Shows age, comment count, and link

Example output: `💻 HN: "ASCII characters are not pixels" — 4h ago — 38 comments`

## Output format
- 8-12 bullets total
- Each bullet should include a source link when available: `Title — (URL)`
- End with **2-3 "things to watch today"** (optionally include links)
- Include: "Not financial advice."
- Keep it concise.

## Post-send hygiene
- Do NOT mark blogwatcher items as read (let the daily digest handle that)
- Do NOT update market-digest-last.txt
