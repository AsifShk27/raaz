---
name: bookmyshow
description: Check movies, showtimes, and seat availability on BookMyShow India. Read-only - does not book tickets. Uses API calls for fast responses.
status: broken
---

# BookMyShow - Movies & Showtimes Checker

> **STATUS: NOT WORKING**
>
> This skill is non-functional. BookMyShow blocks all direct API access via Cloudflare WAF.
> Do not attempt to use this skill - all API calls will fail.
>
> **Reason**: BookMyShow has no public API. They use private B2B integrations with cinema chains.
> The endpoints documented below are reverse-engineered internal APIs that are blocked for non-browser requests.
>
> **Last tested**: January 2026

## Overview

This skill checks what's playing on BookMyShow - movies, theaters, showtimes, and seat availability. It uses direct API calls (no browser needed) for fast responses.

**Capabilities:**
- ✅ List movies now showing in a city
- ✅ Show theaters playing a specific movie
- ✅ Show showtimes and dates
- ✅ Check seat availability (Available/Filling Fast/Sold Out)
- ❌ Does NOT book tickets (read-only)

---

## City Codes

BookMyShow uses region codes. Common ones:

| City | Code |
|------|------|
| Bengaluru | `BANG` |
| Mumbai | `MUMBAI` |
| Delhi-NCR | `NCR` |
| Chennai | `CHEN` |
| Hyderabad | `HYD` |
| Kolkata | `KOLK` |
| Pune | `PUNE` |
| Ahmedabad | `AHME` |

**Default city for this user: Bengaluru (BANG)**

---

## API Endpoints

### 1. Get Movies Now Showing

```bash
curl -s "https://in.bookmyshow.com/api/explore/v1/discover/movie/nowshowing?regionCode=BANG" \
  -H "User-Agent: Mozilla/5.0" \
  -H "Accept: application/json" | jq '.movies[:10]'
```

**Alternative endpoint (more reliable):**
```bash
curl -s "https://in.bookmyshow.com/serv/getData?cmd=QUICKBOOK&type=MT&get498498Data=1&region=BANG" \
  -H "User-Agent: Mozilla/5.0" | jq '.'
```

### 2. Get Movie Details & Showtimes

Once you have a movie code/slug:
```bash
curl -s "https://in.bookmyshow.com/serv/getData?cmd=GETSHOWS&f=json&dc=BANG&ec=ET00012345&dt=20260122" \
  -H "User-Agent: Mozilla/5.0" | jq '.'
```

Parameters:
- `dc` = city code (BANG)
- `ec` = event code (movie ID like ET00012345)
- `dt` = date (YYYYMMDD format)

### 3. Get Venues/Theaters for a Movie

```bash
curl -s "https://in.bookmyshow.com/buytickets/{movie-slug}-{city}/movie-{city}-{movie-code}-MT/{date}" \
  -H "User-Agent: Mozilla/5.0"
```

---

## Python Script (Recommended)

Create and use this script for reliable data fetching:

```python
#!/usr/bin/env python3
"""BookMyShow API Client - Read-only movie/showtime checker"""

import requests
import json
from datetime import datetime, timedelta

BASE_URL = "https://in.bookmyshow.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36",
    "Accept": "application/json",
    "Accept-Language": "en-IN,en;q=0.9",
}

def get_movies_now_showing(city_code="BANG"):
    """Get list of movies currently showing in a city."""
    url = f"{BASE_URL}/api/explore/v1/discover/movie/nowshowing"
    params = {"regionCode": city_code}

    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        return data.get("movies", [])
    except Exception as e:
        # Fallback to QUICKBOOK endpoint
        return get_movies_quickbook(city_code)

def get_movies_quickbook(city_code="BANG"):
    """Fallback: Get movies via QUICKBOOK API."""
    url = f"{BASE_URL}/serv/getData"
    params = {
        "cmd": "QUICKBOOK",
        "type": "MT",
        "region": city_code,
    }
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=10)
        data = resp.json()
        return data.get("moviesData", {}).get("BookMyShow", {}).get("ai498702", [])
    except:
        return []

def get_showtimes(movie_code, city_code="BANG", date=None):
    """Get showtimes for a movie on a specific date."""
    if date is None:
        date = datetime.now().strftime("%Y%m%d")

    url = f"{BASE_URL}/serv/getData"
    params = {
        "cmd": "GETSHOWS",
        "f": "json",
        "dc": city_code,
        "ec": movie_code,
        "dt": date,
    }
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=10)
        return resp.json()
    except:
        return {}

def format_movies(movies, limit=10):
    """Format movie list for display."""
    output = []
    for i, movie in enumerate(movies[:limit], 1):
        name = movie.get("EventTitle") or movie.get("name") or movie.get("mname", "Unknown")
        lang = movie.get("EventLanguage") or movie.get("language", "")
        genre = movie.get("EventGenre") or movie.get("genre", "")
        rating = movie.get("avgRating") or movie.get("rating", "")
        code = movie.get("EventCode") or movie.get("code", "")

        line = f"{i}. **{name}**"
        if lang:
            line += f" ({lang})"
        if genre:
            line += f" | {genre}"
        if rating:
            line += f" | ⭐ {rating}"
        if code:
            line += f"\n   Code: `{code}`"
        output.append(line)
    return "\n\n".join(output)

if __name__ == "__main__":
    import sys
    city = sys.argv[1] if len(sys.argv) > 1 else "BANG"
    movies = get_movies_now_showing(city)
    print(f"Movies now showing in {city}:\n")
    print(format_movies(movies))
```

Save as: `/home/shkas/projects/raaz/skills/bookmyshow/scripts/bms_api.py`

---

## Workflow

### User: "What movies are playing?"

1. **Determine city** (default: Bengaluru)
2. **Fetch movies:**
   ```bash
   python3 /home/shkas/projects/raaz/skills/bookmyshow/scripts/bms_api.py BANG
   ```

3. **Present results:**
   ```
   🎬 Movies now showing in Bengaluru:

   1. **Pushpa 2: The Rule** (Telugu/Hindi)
      Action, Thriller | ⭐ 8.5

   2. **Mufasa: The Lion King** (English/Hindi)
      Animation, Adventure | ⭐ 8.2

   3. **Baby John** (Hindi)
      Action | ⭐ 6.8

   Which movie interests you? I can show showtimes.
   ```

### User: "Show showtimes for Pushpa 2"

1. **Get movie code** from previous response
2. **Ask for date** if not specified:
   ```
   For which date? (Today/Tomorrow/specific date)
   ```

3. **Fetch showtimes:**
   ```bash
   curl -s "https://in.bookmyshow.com/serv/getData?cmd=GETSHOWS&f=json&dc=BANG&ec=ET00412345&dt=20260122" \
     -H "User-Agent: Mozilla/5.0" | jq '.ShowDetails'
   ```

4. **Present theaters and times:**
   ```
   🎬 Pushpa 2: The Rule - Showtimes for Today (Jan 22)

   📍 **PVR Orion Mall, Malleshwaram**
   • 10:30 AM (Telugu) - Available ✅
   • 2:15 PM (Telugu) - Filling Fast 🟡
   • 6:00 PM (Telugu) - Sold Out 🔴
   • 9:45 PM (Telugu) - Available ✅

   📍 **INOX Garuda Mall**
   • 11:00 AM (Hindi) - Available ✅
   • 3:30 PM (Hindi) - Available ✅
   • 7:00 PM (Hindi) - Filling Fast 🟡

   📍 **Cinepolis Royal Meenakshi**
   • 10:00 AM (Telugu) - Available ✅
   • 1:30 PM (Telugu) - Available ✅

   Want details for a specific show? Or book on BookMyShow app/website.
   ```

### User: "Check availability for PVR 6pm show"

1. **Provide booking link:**
   ```
   🎟️ PVR Orion Mall - 6:00 PM (Telugu)
   Status: Sold Out 🔴

   Unfortunately this show is sold out.

   Alternatives:
   • 9:45 PM at same theater - Available ✅
   • 7:00 PM at INOX Garuda - Filling Fast 🟡

   To book, open: https://in.bookmyshow.com/buytickets/pushpa-2-the-rule-bengaluru/movie-bang-ET00412345-MT/20260122
   ```

---

## Error Handling

### API Not Responding
```
BookMyShow API is slow. Let me try again...
```
Retry once. If still fails:
```
BookMyShow seems to be having issues. Try:
• Open https://in.bookmyshow.com directly
• Check back in a few minutes
```

### Movie Not Found
```
I couldn't find "{movie_name}" in the current listings.
Did you mean one of these?
1. Pushpa 2: The Rule
2. Pushpa: The Rise (might not be showing)

Or tell me the exact name as shown on BookMyShow.
```

### City Not Recognized
```
I don't recognize that city. Try:
• Bengaluru, Mumbai, Delhi, Chennai, Hyderabad
• Or give me the BookMyShow city code (like BANG, MUMBAI)
```

---

## Quick Commands

| User Says | Action |
|-----------|--------|
| "What's playing?" | List movies in default city |
| "Movies in Mumbai" | List movies with city=MUMBAI |
| "Pushpa 2 showtimes" | Get showtimes for that movie |
| "Tomorrow's shows" | Use tomorrow's date |
| "This weekend" | Show Sat/Sun dates |

---

## Notes

- **No booking**: This skill only checks info. To book, user opens BookMyShow app/website
- **Data freshness**: Availability changes fast. Always fetch fresh data
- **Rate limiting**: Don't spam requests. One fetch per user query is enough
- **Default city**: Bengaluru (BANG) - change in USER.md if needed
