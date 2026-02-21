#!/bin/bash
# DuckDuckGo Search Integration for Clawdbot
# Usage: ddg-search "your query here"

export PATH="$HOME/.local/bin:$PATH"

# Run the search and format output for WhatsApp
python3 /home/shkas/projects/raaz/skills/duckduckgo-search/scripts/duckduckgo-search.py "$@" --num 5
