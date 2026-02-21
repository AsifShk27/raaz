---
name: india-ordering
description: Unified ordering router for India delivery services (Zomato, Swiggy, BigBasket, Blinkit, Zepto). Routes to appropriate service skill and handles tracking. Never places orders without explicit user confirmation.
---

# India Ordering - Router Skill

## ⛔ MANDATORY EXECUTION RULES ⛔

### THE #1 CAUSE OF FAILURE: Outputting text before clicking

**EVERY CLICK MUST FOLLOW THIS EXACT SEQUENCE:**

```
1. openclaw browser snapshot --format aria
2. openclaw browser click <ref>           ← IMMEDIATELY, NO TEXT OUTPUT FIRST
3. THEN output text to user
```

### ❌ FORBIDDEN - This WILL fail:

```
openclaw browser snapshot --format aria    # Got ref ax18
"I found the button, let me click it..."   ← ⛔ THIS TEXT OUTPUT MAKES ax18 STALE
openclaw browser click ax18                # FAILS: TimeoutError 8000ms
```

### ✅ CORRECT - This works:

```
openclaw browser snapshot --format aria    # Got ref ax18
openclaw browser click ax18                # Works! Click happens immediately
"I clicked the button."                    # Talk AFTER the click
```

### WHY: The moment you output ANY text, seconds pass. The page re-renders. The ref no longer exists.

### ERROR RECOVERY:
If you get `TimeoutError: locator.click: Timeout 8000ms exceeded`:
1. You used a stale ref
2. Take a NEW snapshot
3. Find the NEW ref
4. Click IMMEDIATELY (no text first)

### 🛑 PRE-CLICK CHECKLIST (VERIFY BEFORE EVERY CLICK):
Before EVERY `openclaw browser click` command, ask yourself:
- [ ] Did I just run `openclaw browser snapshot` in my PREVIOUS tool call?
- [ ] Have I output ANY text since that snapshot? If YES → snapshot again!
- [ ] Am I about to click IMMEDIATELY in my NEXT tool call?

If you answered NO to any of these → STOP and take a fresh snapshot first.

### ⚠️ SINGLE AGENT RULE - CRITICAL ⚠️

**DO NOT spawn multiple sub-agents for this task.**

- Use ONE agent to control the browser from start to finish
- Do NOT spawn a new sub-agent if one is already running
- Do NOT run browser commands from multiple agents in parallel
- If a sub-agent times out or fails, WAIT for it to finish before spawning another

**WHY:** Multiple agents fighting over the same browser = chaos. Each agent invalidates the other's refs.

### ⚠️ IF YOU ARE A SUB-AGENT - READ THIS ⚠️

**DO NOT use the message tool to send results back to the user.**

If you were spawned by a parent agent:
1. Complete your task (browser automation, data collection)
2. Simply OUTPUT your results as plain text in your final response
3. The announce flow will automatically deliver your results to the user
4. Do NOT try to send WhatsApp/Discord/etc messages yourself - you lack the `--to` context

**WHY:** Sub-agents don't have the original sender's address. The parent's announce flow handles delivery.

---

## 🌐 URL-BASED NAVIGATION (CRITICAL!)

### Why URL-Based Navigation?

Clicking dynamic elements on Indian food/grocery SPAs causes:
1. **Stale refs** - Elements re-render before click completes
2. **Wrong tab/section** - Lands on wrong page (e.g., "Dining Out" vs "Delivery")
3. **Language changes** - Clicking wrong elements can trigger location/language corruption

**SOLUTION: Use direct URLs instead of clicking tabs/search elements.**

### Service URL Patterns

| Service | Home URL | Search URL Pattern |
|---------|----------|-------------------|
| Zomato | `https://www.zomato.com/bangalore/delivery` | `https://www.zomato.com/bangalore/delivery?query={term}` |
| Swiggy | `https://www.swiggy.com/` | `https://www.swiggy.com/search?query={term}` |
| BigBasket | `https://www.bigbasket.com/` | `https://www.bigbasket.com/ps/?q={term}` |
| Blinkit | `https://blinkit.com/` | `https://blinkit.com/s/?q={term}` |
| Zepto | `https://www.zeptonow.com/` | `https://www.zeptonow.com/search?query={term}` |

### Language/Location Corruption Recovery

If you see Turkish ("Yemeğe Çık"), or any non-English text:
1. **DO NOT click any elements** - clicking makes it worse
2. Navigate directly to service's home URL
3. URL navigation will reset language/location

---

## 📍 CRITICAL: Location Handling for All Services

### The Problem (Applies to Zomato, Swiggy, BigBasket, etc.)

**URL navigation sets the CITY but NOT the specific delivery address!**

- `https://www.zomato.com/bangalore/delivery` → Sets city to Bangalore
- Does NOT select user's saved address (like "Home - Bohra Layout, Gottigere")
- Location can reset after any navigation or search

### The Solution (MANDATORY)

**After EVERY URL navigation:**
1. Take a snapshot and check the location in the header
2. If location shows just city name or wrong location, click location dropdown
3. Select the user's saved address (usually "Home")
4. Verify header shows the specific address BEFORE proceeding

### Default User Address

For this user, the default delivery address is:
- **Home:** Bohra Layout, Gottigere, Bengaluru 560083

If location shows anything else (Mumbai, Delhi, "Bandra Kurla Complex", just "Bangalore"), it's WRONG and must be fixed.

---

## Overview

This skill routes food and grocery orders to the appropriate service skill (Zomato, Swiggy, BigBasket, Blinkit, Zepto) based on user intent.

## Critical Rules (Apply to ALL Services)

### Rule 1: Fresh Snapshot Before Every Click

All Indian food/grocery sites are dynamic SPAs. **Click BEFORE talking.**

### Rule 2: Only Report Visible Data

**NEVER hallucinate.** If you can't see a price, rating, or ETA in the snapshot, don't include it.

### Rule 3: User Chooses Everything

- User picks the restaurant/store
- User picks menu items/products
- User confirms cart
- User confirms payment
- **NEVER auto-select or auto-checkout**

### Rule 4: Explicit Confirmation Before Payment

Always show full order summary and wait for explicit "yes" before checkout.

---

## Service Routing

### Identify Service

| User says | Route to |
|-----------|----------|
| "Zomato", "order from Zomato" | `zomato-ordering` |
| "Swiggy", "order from Swiggy" | `swiggy-ordering` |
| "BigBasket", "BB", "groceries" | `bigbasket-ordering` |
| "Blinkit", "quick commerce" | Blinkit workflow below |
| "Zepto" | Zepto workflow below |
| Restaurant/food names | Ask: "Zomato or Swiggy?" |
| Grocery items | Ask: "BigBasket or Blinkit/Zepto?" |
| "Where's my order?" | Ask which service |

### Intent Detection

| Intent | Keywords |
|--------|----------|
| **Food ordering** | biryani, pizza, burger, restaurant, dinner, lunch, food |
| **Grocery ordering** | dal, rice, oil, atta, vegetables, milk, eggs, groceries |
| **Quick commerce** | quick, 10 minutes, instant, Blinkit, Zepto |
| **Order tracking** | where, track, status, delivery, arriving |

---

## Service Skills

### Food Delivery

**Zomato** → Use `zomato-ordering` skill
- Full restaurant discovery with ratings, delivery time, distance
- Menu browsing with categories
- Cart with offers and customization
- Payment method selection
- Order tracking

**Swiggy** → Use `swiggy-ordering` skill
- Similar flow to Zomato
- Includes Swiggy Money wallet
- Instamart integration (groceries)

### Grocery Delivery

**BigBasket** → Use `bigbasket-ordering` skill
- Product search with brand/size options
- Delivery slot selection (critical!)
- Substitution preferences
- Shopping list mode

### Quick Commerce

**Blinkit/Zepto** → See workflow below

---

## Quick Commerce Workflow (Blinkit/Zepto)

For Blinkit and Zepto, follow this workflow:

### Setup

```bash
openclaw browser start
openclaw browser open https://blinkit.com/  # or https://www.zeptonow.com/
```

Wait 2-3 seconds:
```bash
openclaw browser snapshot --format aria
```

### Check Login

**Logged IN:** User name, saved addresses
**Logged OUT:** "Login" button

If not logged in:
```
You need to log in to Blinkit. Should I open login?
Complete OTP yourself, then say "done".
```

### Set Location

```bash
openclaw browser snapshot --format aria
openclaw browser click <location-ref>
```

Show saved addresses or enter pincode.

### Search & Add Items (URL-BASED - PREFERRED)

**⚠️ USE URL-BASED SEARCH TO AVOID STALE REFS!**

```bash
# For Blinkit:
openclaw browser navigate "https://blinkit.com/s/?q=butter"

# For Zepto:
openclaw browser navigate "https://www.zeptonow.com/search?query=butter"
```

Wait for results:
```bash
openclaw browser snapshot --format aria
```

**FALLBACK: Click-based search (only if URL search fails)**

```bash
openclaw browser snapshot --format aria
openclaw browser click <search-ref>
openclaw browser snapshot --format aria
openclaw browser type <input-ref> "item name"
openclaw browser press Enter
openclaw browser snapshot --format aria
```

**Present options:**
```
I found these options:

1. **Amul Butter** - 500g - ₹275
2. **Amul Butter** - 200g - ₹115
3. **Britannia Butter** - 500g - ₹265

Which one?
```

**Wait for choice, then add:**
```bash
openclaw browser snapshot --format aria
openclaw browser click <add-ref>
```

### Review Cart

```
🛒 **Your Blinkit Order**

• Amul Butter 500g - ₹275
• Bread - ₹45

Total: ₹320
Delivery: 10 min ⚡

Proceed to checkout?
```

### Checkout

Only after "yes":
```bash
openclaw browser snapshot --format aria
openclaw browser click <checkout-ref>
```

Show payment options, wait for choice, then:
```
Payment ready. Complete it yourself, or say "place order" for me to click.
```

---

## Order Tracking Workflow

### Identify Service

```
Which service do you want to track?
1. Zomato
2. Swiggy
3. BigBasket
4. Blinkit
5. Zepto
```

### Open Tracking Page

```bash
openclaw browser start
openclaw browser open <orders-url>
```

URLs:
- Zomato: `https://www.zomato.com/orders`
- Swiggy: `https://www.swiggy.com/my-account/orders`
- BigBasket: `https://www.bigbasket.com/my-account/orders`
- Blinkit: `https://blinkit.com/orders`
- Zepto: `https://www.zeptonow.com/account/orders`

### Check Login & Report Status

```bash
openclaw browser snapshot --format aria
```

If logged in, find active order and report:
```
📦 **Order Status**

Service: Swiggy
Restaurant: Paradise Biryani
Order ID: SWG123456

Status: Out for Delivery 🚴
ETA: 10 minutes (7:45 PM)

Delivery partner: Rahul - 98765XXXXX

Want updates?
```

---

## Error Handling

### Service Unavailable

```
⚠️ Blinkit doesn't deliver to your area.

Alternatives:
1. Try Zepto
2. Try BigBasket (slower delivery)
3. Enter different address
```

### Item Not Available

```
⚠️ This item isn't available on Blinkit.

Should I:
1. Check Zepto for this item?
2. Find alternatives on Blinkit?
3. Skip this item?
```

### Browser Issues

```bash
openclaw browser status
openclaw browser stop
openclaw browser start
```

---

## Command Reference

| Action | Command |
|--------|---------|
| Start browser | `openclaw browser start` |
| Stop browser | `openclaw browser stop` |
| Status | `openclaw browser status` |
| Open URL | `openclaw browser open <url>` |
| Navigate | `openclaw browser navigate <url>` |
| Snapshot | `openclaw browser snapshot --format aria` |
| Screenshot | `openclaw browser screenshot` |
| Click | `openclaw browser click <ref>` |
| Type | `openclaw browser type <ref> "text"` |
| Key press | `openclaw browser press Enter` |

---

## Best Practices Summary

1. **Route correctly** - Ask if service unclear
2. **Fresh snapshot before every click** - SPAs have stale refs
3. **Only report visible data** - Never guess prices
4. **User picks everything** - Never auto-select
5. **Confirm before payment** - Explicit "yes" required
6. **Handle errors gracefully** - Screenshot, retry, ask user
7. **Be transparent** - Tell user what's happening
8. **Offer alternatives** - If something unavailable
9. **Be CONCISE** - Don't narrate every action. Skip "Let me...", "I'll now...", "I'm going to..."

## ⚡ Output Efficiency Rules

**DO NOT narrate your actions.** Users don't need a play-by-play.

❌ **BAD (verbose):**
```
Let me take a snapshot to see what's on the screen.
Now I'll look for the search results.
I can see several restaurants. Let me parse them for you.
```

✅ **GOOD (concise):**
```
Found 4 biryani restaurants:
1. **Meghana Foods** ⚡ 20-25 min | 2.1 km ...
```

**Rules:**
- Skip phrases like "Let me...", "I'll...", "Now I'm going to..."
- Don't announce tool calls before making them
- Go straight to results
- Only explain when something unexpected happens or fails
