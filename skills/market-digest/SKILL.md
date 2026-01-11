---
name: market-digest
description: Generate and send a daily financial markets digest (India + global) using RSS (blogwatcher) and optional web search via the browser tool. Includes once-per-day guard.
metadata: {"clawdbot":{"emoji":"📈","requires":{"bins":["blogwatcher"]}}}
---

# market-digest

Generate a **daily financial markets** summary for Asif.

## Inputs
- Timezone: `Asia/Kolkata`
- Delivery surface: WhatsApp (main session)
- Idempotency marker: `/home/shkas/projects/raaz/memory/market-digest-last.txt`

## Once-per-day guard
1. Read `/home/shkas/projects/raaz/memory/market-digest-last.txt` if it exists.
2. If it contains today’s IST date (`YYYY-MM-DD`), **do nothing**.
3. Otherwise, generate and send digest, then write today’s IST date + timestamp to the file.

## Sources
### RSS (primary)
Use `blogwatcher`:
- `blogwatcher scan`
- `blogwatcher articles` (prefer items published in last ~24–36h)

Tracked feeds should include:
- Economic Times Markets
- Economic Times Economy
- Moneycontrol Top News
- Moneycontrol Markets
- RBI Publications

### Web search (optional, for context)
Use the `browser` tool to quickly sanity-check “big picture” moves:
- US indices overnight move
- USD/INR, crude, gold
- Any major macro event (CPI, FOMC, RBI, budget headlines)

Keep web usage light: 3–6 quick queries.

## Output format
- 8–12 bullets total
- Each bullet should include a source link when available: `Title — (URL)`
- End with **2–3 “things to watch today”** (optionally include links if they reference a specific article/event)
- Include: “Not financial advice.”
- Keep it concise.

## Post-send hygiene
- Mark items read in blogwatcher to avoid repeats (either `blogwatcher read <id>` for used items, or `blogwatcher read-all` if acceptable).
