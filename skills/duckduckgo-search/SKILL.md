---
name: duckduckgo-search
description: Lightweight web search CLI using DuckDuckGo HTML with Bing RSS and SearXNG fallbacks.
---

# DuckDuckGo Search Skill

A lightweight web search skill using DuckDuckGo HTML + Bing RSS + SearXNG - no API key required!

## Installation

The `ddg` CLI is located at `scripts/duckduckgo-search.py`.

### Make it executable and add to PATH:
```bash
chmod +x /home/shkas/projects/raaz/skills/duckduckgo-search/scripts/duckduckgo-search.py

# Add to PATH (add to ~/.bashrc for persistence)
ln -sf /home/shkas/projects/raaz/skills/duckduckgo-search/scripts/duckduckgo-search.py ~/.local/bin/ddg

# For current session:
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
# Basic search
ddg "your query here"

# Get 5 results
ddg "python tutorials" --num 5

# JSON output (for scripting)
ddg "weather bangalore" --json
```

## Examples

```
$ ddg "Kyutai Pocket TTS"

🔍 Searching for: Kyutai Pocket TTS...

📋 Search Results:

================================================================================
1. kyutai-labs/pocket-tts: A TTS that fits in your CPU (and pocket) - GitHub
   → https://kyutai.org/

2. Kyutai - Hugging Face
   → https://github.com/kyutai-labs/pocket-tts

3. Kyutai - Voice AI Tool
   → https://huggingface.co/kyutai
================================================================================

$ ddg "fastapi tutorial" --json
[
  {
    "title": "FastAPI Tutorial",
    "url": "https://fastapi.tiangolo.com/tutorial/"
  },
  ...
]
```

## Options

| Flag | Description |
|------|-------------|
| `-n, --num N` | Number of results (default: 10) |
| `-j, --json` | Output results as JSON |

## Features

- ✅ No API key required
- ✅ No browser needed
- ✅ Free and unlimited
- ✅ Multi-backend (DuckDuckGo → Bing → SearXNG fallback)
- ✅ Simple CLI interface
- ✅ JSON output for scripting

## How It Works

1. **Primary**: DuckDuckGo HTML (`html.duckduckgo.com`)
2. **Fallback 1**: Bing RSS with English filter
3. **Fallback 2**: Public SearXNG instances

Automatically falls back if primary source fails or is rate-limited.

## Notes

- DuckDuckGo may show CAPTCHA for automated requests - script auto-falls back
- Bing RSS provides English results by default
- For heavy usage, consider self-hosted SearXNG

## Comparison with Other Search Methods

| Method | API Key | Browser | Cost |
|--------|---------|---------|------|
| **ddg (this skill)** | ❌ | ❌ | Free |
| Brave Search | ✅ | ❌ | Paid |
| Google Custom Search | ✅ | ❌ | Free tier |
| Browser automation | ❌ | ✅ | Free |

## Alternative: Using in Python Scripts

```python
import subprocess
import json

result = subprocess.run(
    ['ddg', '--json', 'your query'],
    capture_output=True,
    text=True
)
results = json.loads(result.stdout)
```
