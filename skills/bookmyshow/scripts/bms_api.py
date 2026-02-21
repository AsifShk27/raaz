#!/usr/bin/env python3
"""
BookMyShow API Client - Read-only movie/showtime checker
Uses reverse-engineered internal APIs (unofficial)
"""

import requests
import json
import sys
from datetime import datetime, timedelta

BASE_URL = "https://in.bookmyshow.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-IN,en;q=0.9",
    "Referer": "https://in.bookmyshow.com/",
}

CITY_CODES = {
    "bengaluru": "BANG", "bangalore": "BANG", "blr": "BANG",
    "mumbai": "MUMBAI", "bom": "MUMBAI",
    "delhi": "NCR", "ncr": "NCR", "noida": "NCR", "gurgaon": "NCR",
    "chennai": "CHEN", "madras": "CHEN",
    "hyderabad": "HYD",
    "kolkata": "KOLK", "calcutta": "KOLK",
    "pune": "PUNE",
    "ahmedabad": "AHME",
    "kochi": "KOCH", "cochin": "KOCH",
    "jaipur": "JAIP",
    "chandigarh": "CHD",
}

def get_city_code(city_input):
    """Convert city name to BookMyShow region code."""
    city_lower = city_input.lower().strip()
    if city_lower in CITY_CODES:
        return CITY_CODES[city_lower]
    # Check if already a code
    if city_input.upper() in ["BANG", "MUMBAI", "NCR", "CHEN", "HYD", "KOLK", "PUNE", "AHME"]:
        return city_input.upper()
    return None

def get_movies_quickbook(city_code="BANG"):
    """Get movies via QUICKBOOK API (most reliable)."""
    url = f"{BASE_URL}/serv/getData"
    params = {
        "cmd": "QUICKBOOK",
        "type": "MT",
        "region": city_code,
    }
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()

        # Navigate the nested structure
        movies_data = data.get("moviesData", {})
        bms = movies_data.get("BookMyShow", {})

        # Try different possible keys
        movies = []
        for key, value in bms.items():
            if isinstance(value, list) and len(value) > 0:
                movies = value
                break

        return movies
    except Exception as e:
        print(f"Error fetching movies: {e}", file=sys.stderr)
        return []

def get_movies_explore_api(city_code="BANG"):
    """Get movies via explore API (alternative)."""
    url = f"{BASE_URL}/api/explore/v1/discover/movie"
    params = {
        "regionCode": city_code,
        "page": 1,
        "size": 30,
    }
    try:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        return data.get("data", {}).get("movies", [])
    except Exception as e:
        return []

def get_movies(city_code="BANG"):
    """Get movies - tries multiple endpoints."""
    movies = get_movies_quickbook(city_code)
    if not movies:
        movies = get_movies_explore_api(city_code)
    return movies

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
        resp = requests.get(url, headers=HEADERS, params=params, timeout=15)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"Error fetching showtimes: {e}", file=sys.stderr)
        return {}

def format_movies_list(movies, limit=15):
    """Format movie list for display."""
    if not movies:
        return "No movies found."

    output = []
    for i, movie in enumerate(movies[:limit], 1):
        # Handle different response structures
        name = (movie.get("EventTitle") or movie.get("mname") or
                movie.get("name") or movie.get("n") or "Unknown")
        lang = (movie.get("EventLanguage") or movie.get("mlang") or
                movie.get("language") or movie.get("l") or "")
        genre = (movie.get("EventGenre") or movie.get("mgenre") or
                 movie.get("genre") or movie.get("g") or "")
        rating = (movie.get("avgRating") or movie.get("mrating") or
                  movie.get("rating") or movie.get("r") or "")
        code = (movie.get("EventCode") or movie.get("mcode") or
                movie.get("code") or movie.get("c") or "")

        line = f"{i}. {name}"
        details = []
        if lang:
            details.append(lang)
        if genre:
            details.append(genre)
        if rating:
            details.append(f"⭐ {rating}")

        if details:
            line += f" | {' | '.join(details)}"
        if code:
            line += f"\n   [Code: {code}]"

        output.append(line)

    return "\n\n".join(output)

def format_showtimes(data):
    """Format showtime data for display."""
    shows = data.get("ShowDetails", [])
    if not shows:
        return "No showtimes found for this movie/date."

    # Group by venue
    venues = {}
    for show in shows:
        venue_name = show.get("VenueName", "Unknown Venue")
        if venue_name not in venues:
            venues[venue_name] = []
        venues[venue_name].append(show)

    output = []
    for venue, venue_shows in venues.items():
        output.append(f"\n📍 {venue}")
        for show in venue_shows:
            time = show.get("ShowTime", "")
            lang = show.get("Language", "")
            avail = show.get("Availability", "")

            # Availability indicator
            if "sold" in avail.lower():
                status = "🔴 Sold Out"
            elif "fast" in avail.lower():
                status = "🟡 Filling Fast"
            else:
                status = "✅ Available"

            time_line = f"   • {time}"
            if lang:
                time_line += f" ({lang})"
            time_line += f" - {status}"
            output.append(time_line)

    return "\n".join(output)

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  List movies:    python bms_api.py movies [city]")
        print("  Get showtimes:  python bms_api.py shows <movie_code> [city] [date:YYYYMMDD]")
        print("\nExamples:")
        print("  python bms_api.py movies bangalore")
        print("  python bms_api.py shows ET00412345 BANG 20260122")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "movies":
        city_input = sys.argv[2] if len(sys.argv) > 2 else "BANG"
        city_code = get_city_code(city_input) or city_input.upper()

        print(f"🎬 Fetching movies in {city_code}...\n")
        movies = get_movies(city_code)
        print(format_movies_list(movies))
        print(f"\n--- {len(movies)} movies found ---")

    elif command == "shows" or command == "showtimes":
        if len(sys.argv) < 3:
            print("Error: Movie code required")
            print("Usage: python bms_api.py shows <movie_code> [city] [date]")
            sys.exit(1)

        movie_code = sys.argv[2]
        city_input = sys.argv[3] if len(sys.argv) > 3 else "BANG"
        city_code = get_city_code(city_input) or city_input.upper()
        date = sys.argv[4] if len(sys.argv) > 4 else datetime.now().strftime("%Y%m%d")

        print(f"🎬 Fetching showtimes for {movie_code} in {city_code} on {date}...\n")
        data = get_showtimes(movie_code, city_code, date)
        print(format_showtimes(data))

    else:
        print(f"Unknown command: {command}")
        print("Use 'movies' or 'shows'")
        sys.exit(1)

if __name__ == "__main__":
    main()
