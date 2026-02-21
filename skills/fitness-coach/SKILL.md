---
name: fitness-coach
description: Personalized daily-wellbeing coach for practical movement, nutrition, and recovery nudges with anti-repetition rotation.
metadata: {"openclaw":{"emoji":"💪","category":"health"}}
---

# Fitness Coach

A compassionate coaching skill for short daily nudges focused on sustainable routines:
- Gentle movement for back/knee/leg comfort
- Cleaner meal and hydration habits
- Sleep-friendly evening routines
- Consistent low-pressure progress

## Target Profile
- Back pain, leg pain, and knee pain sensitivity
- Needs practical, repeatable routine guidance
- Prefers supportive, non-judgmental language

## Approach
1. **Gentle encouragement** - Never judgmental, always supportive
2. **Low-impact exercises** - Water aerobics, chair exercises, walking, stretching
3. **Anti-inflammatory diet focus** - Reduce processed foods, increase vegetables
4. **Small wins** - Celebrate every achievement, no matter how small
5. **Pain-aware recommendations** - Always consider joint health

## Usage
This skill powers recurring WhatsApp coaching nudges via cron.

### Anti-repetition engine

- Local generator script:
  - `/home/shkas/projects/raaz/skills/fitness-coach/scripts/compose_nudge.py`
- Persistent state:
  - `~/.openclaw/state/fitness-coach/rotation_state.json`
- Current guardrails:
  - blocks repeating same tip across last 8 runs and within last 24 hours (fallback when pool exhausted)
  - blocks explicit message terms: `liver`, `fitness`, `weight loss`, `obese`, `kg`
