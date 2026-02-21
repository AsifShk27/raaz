---
name: aws-certification-coach
description: Personalized AWS certification coaching with SAP-C02-first study planning, domain-based drills, mock review, and progress tracking. Use when users ask to prepare for AWS certifications, build a roadmap to exam day, run practice sessions, or analyze readiness gaps.
---

# AWS Certification Coach

This skill provides a repeatable coaching workflow for AWS certification prep.
Default track: AWS Certified Solutions Architect - Professional (SAP-C02).

## Coaching Workflow

1. Confirm the target exam and exam date.
- If the user says "Solutions Architect Professional", default to `SAP-C02`.
- If the exam is not specified, ask before building a plan.

2. Verify mutable facts from official AWS pages when the user asks for "latest/current" details.
- Use `references/sap-c02-official-baseline.md` as the starting baseline.
- Re-check official URLs before sharing exam metadata that may change.

3. Create or update a learner profile.
```bash
python3 scripts/coach.py list-profiles
python3 scripts/coach.py init-profile --name "<name>" --target-date YYYY-MM-DD --weekly-hours 8
python3 scripts/coach.py update-profile --profile <profile.json> --set-confidence "domain-1=2,domain-2=3"
```
- Profiles are stored under `~/.openclaw/state/aws-certification-coach/` (for example `asif-profile.json`).

4. Generate a weighted study plan from domain weights and confidence gaps.
```bash
python3 scripts/coach.py generate-plan --profile <profile.json> --output <study-plan.md>
```

5. Generate focused session packs and run domain drills.
```bash
python3 scripts/coach.py generate-session --profile <profile.json> --domain domain-2 --minutes 90 --output <session.md>
```

6. Run adaptive daily drill (basics-first, auto-leveling) and check answers.
```bash
python3 scripts/coach.py daily-brief --profile <profile.json>
python3 scripts/coach.py check-answers --profile <profile.json> --session-id <session-id> --answers A,B,C
```

WhatsApp zero-model grading command:
```text
/sap_ans <session-id> A,B,C
```
- This command is handled by OpenClaw plugin command routing and does not depend on model reasoning.
- If you omit `<session-id>`, the command grades against the latest generated adaptive session.
- Grading is idempotent per session: once a session is graded, repeated `/sap_ans` returns the existing result without changing profile history again.

7. Log outcomes and refresh readiness.
```bash
python3 scripts/coach.py log-session --profile <profile.json> --domain domain-2 --score 78 --notes "<summary>"
python3 scripts/coach.py progress-report --profile <profile.json>
```

## Output Standards

- Anchor exam facts to official AWS certification sources.
- Map coaching advice to SAP-C02 domain/task language.
- Separate policy facts from inferred coaching strategy.
- Keep plans realistic: revision blocks, timed practice, and error-log review.
- Never claim access to real exam questions.

## Files

- `references/domain-blueprint.json`: SAP-C02 domains, task statements, and weights.
- `references/sap-c02-official-baseline.md`: official source snapshot and links.
- `scripts/coach.py`: deterministic planning and tracking CLI.
- `scripts/coach_common.py`: shared profile/date/allocation utilities.
- `scripts/coach_adaptive.py`: adaptive basics-first drill generation, answer checking, and level progression.
- `scripts/coach_render.py`: markdown rendering for plans, sessions, and progress reports.
- `assets/profile-template.json`: profile template for manual edits.
