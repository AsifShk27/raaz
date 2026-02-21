---
name: swiggy-ordering
description: Order food from Swiggy in India via OpenClaw browser automation. Handles restaurant discovery, menu browsing, cart management, offers, and checkout. Never places orders or makes payments without explicit user confirmation.
---

# Swiggy Ordering - Production Guide

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
"I found the login button, let me click it..."   ← ⛔ THIS TEXT OUTPUT MAKES ax18 STALE
openclaw browser click ax18                # FAILS: TimeoutError 8000ms
```

### ✅ CORRECT - This works:

```
openclaw browser snapshot --format aria    # Got ref ax18
openclaw browser click ax18                # Works! Click happens immediately
"I clicked the login button."              # Talk AFTER the click
```

### WHY: The moment you output ANY text, seconds pass. Swiggy re-renders. The ref no longer exists.

### ERROR RECOVERY:
If you get `TimeoutError: locator.click: Timeout 8000ms exceeded`:
1. You used a stale ref
2. Take a NEW snapshot
3. Find the NEW ref
4. Click IMMEDIATELY (no text first)

### ⚠️ SINGLE AGENT RULE - CRITICAL ⚠️

**DO NOT spawn multiple sub-agents for this task.**

- Use ONE agent to control the browser from start to finish
- Do NOT spawn a new sub-agent if one is already running
- Do NOT run browser commands from multiple agents in parallel
- If a sub-agent times out or fails, WAIT for it to finish before spawning another

**WHY:** Multiple agents fighting over the same browser = chaos. Each agent invalidates the other's refs.

---

## 📍 LOCATION HANDLING (THE #2 CAUSE OF FAILURE)

### The Problem

**URL navigation does NOT set the delivery address!**

- Navigating to `https://www.swiggy.com/` does NOT select user's saved address
- Location can reset when navigating or searching
- Wrong location = wrong restaurants, wrong delivery estimates

### Common Wrong Location Signs

- Header shows generic location or wrong area
- Header shows different city (Mumbai instead of Bangalore)
- Restaurants show unusually long delivery times

### The Fix (MANDATORY EVERY TIME)

**After EVERY URL navigation, you MUST:**

1. Take a snapshot and check the location in the header
2. If location is wrong, click the location dropdown
3. Select the user's saved "Home" address
4. Verify the header shows correct address BEFORE proceeding

### Default User Address

For this user, the default delivery address is:
- **Home:** Bohra Layout, Gottigere, Bengaluru 560083

If location shows anything else, it's WRONG and must be fixed.

---

## 🌐 URL-BASED NAVIGATION (CRITICAL!)

### Why URL-Based Navigation?

Clicking dynamic elements on Swiggy causes:
1. **Stale refs** - Elements re-render before click completes
2. **Wrong section** - May land on Instamart instead of Food
3. **Location changes** - Clicking wrong elements can trigger location changes

**SOLUTION: Use direct URLs instead of clicking elements where possible.**

### URL Patterns

| Action | URL Pattern |
|--------|-------------|
| Food home | `https://www.swiggy.com/` |
| Instamart (groceries) | `https://www.swiggy.com/instamart` |
| Search food | `https://www.swiggy.com/search?query={search_term}` |
| Restaurant page | `https://www.swiggy.com/restaurants/{restaurant-slug}` |

### Language/Location Corruption Recovery

If you see unexpected text or wrong location:
1. **DO NOT click random elements** - may worsen the issue
2. Navigate directly to: `https://www.swiggy.com/`
3. Verify location in header before proceeding

---

## Overview

This skill uses OpenClaw's browser automation (Playwright-based) to help users order food from Swiggy. It handles the complete flow from restaurant discovery to checkout, with full user control at every step.

## Critical Rules

### Rule 1: Fresh Snapshot Before Every Action

Swiggy is a dynamic SPA. Element refs become stale within seconds. **Click BEFORE talking.**

### Rule 2: Only Report What You Actually See

**NEVER hallucinate or guess data.** If you can't see a price, rating, or distance in the snapshot, don't include it.

### Rule 3: User Confirms Everything

- User picks the restaurant
- User picks menu items
- User confirms cart before checkout
- **NEVER click "Place Order" or "Pay" without explicit "yes" from user**

### Rule 4: Handle Errors Gracefully

If something fails:
1. Take a screenshot to see what's on screen
2. Take a fresh snapshot
3. Try to understand the current state
4. Either retry or ask user for help

---

## Understanding ARIA Snapshots

When you run `openclaw browser snapshot --format aria`, you get accessibility tree output:

```
document [ref=ax1]
  banner [ref=ax2]
    link "Swiggy" [ref=ax3]
    button "Sign in" [ref=ax4]
    searchbox "Search for restaurants and food" [ref=ax5]
  main [ref=ax6]
    article [ref=ax7]
      link "Paradise Biryani" [ref=ax8]
      text "4.2"
      text "20-25 min"
      text "₹250 for two"
```

**Key points:**
- Use `ref` values (ax8, ax10, etc.) for clicking
- Text content appears after element type
- Restaurant cards are usually `article` or `listitem` elements

---

## Complete Workflow

### Phase 1: Setup

#### Step 1.1: Start Browser

```bash
openclaw browser start
```

If fails:
```bash
openclaw browser status
openclaw browser stop
openclaw browser start
```

#### Step 1.2: Open Swiggy

```bash
openclaw browser open https://www.swiggy.com/
```

Wait 2-3 seconds, then:
```bash
openclaw browser snapshot --format aria
```

**Verify:** Look for "Swiggy" logo, search bar, "Food"/"Instamart" tabs.

---

### Phase 2: Authentication

#### Step 2.1: Check Login Status

Examine header for:

**Logged IN:** User name, profile icon, "My Account"
**Logged OUT:** "Sign in" or "Login" button

#### Step 2.2: Handle Login (AUTOMATIC - don't ask permission)

**If user is NOT logged in, AUTOMATICALLY click the login button:**

```bash
openclaw browser snapshot --format aria
# Find "Sign in" or "Login" button in header
openclaw browser click <login-button-ref>
openclaw browser snapshot --format aria
```

**Tell user (after clicking login):**
```
I've opened the Swiggy login popup for you. Please:
1. Enter your phone number
2. Complete OTP verification
3. Say "done" when logged in

I'll wait for you.
```

**If already logged in:**
```
You're already logged in to Swiggy. Let me find biryani for you...
```
Then skip to Phase 3.

**STOP AND WAIT for user to say "done".**

After user confirms:
```bash
openclaw browser snapshot --format aria
```
Verify login succeeded by looking for user name in header.

---

### Phase 3: Location Setup (CRITICAL - MUST SELECT SAVED ADDRESS)

#### ⚠️ IMPORTANT: URL Navigation Does NOT Set Delivery Address!

The location in the header may be wrong even after navigating to Swiggy. You MUST explicitly select a saved address.

#### Step 3.1: ALWAYS Click Location Dropdown (MANDATORY)

**Even if location looks correct, you MUST verify and select a saved address:**

```bash
openclaw browser snapshot --format aria
# Find location button/dropdown in header
openclaw browser click <location-ref>
openclaw browser snapshot --format aria
```

#### Step 3.2: Select Saved Address (MANDATORY)

**Present saved addresses to user:**
```
I see these saved addresses:
1. Home - Bohra Layout, Gottigere, Bengaluru
2. Work - Ecospace Business Park, Bellandur

Which address should I deliver to? (say the number)
```

**Wait for user to choose, then click the saved address:**
```bash
openclaw browser snapshot --format aria
openclaw browser click <saved-address-ref>
```

**Verify address was set:**
```bash
openclaw browser snapshot --format aria
```

Look in the header - it should now show the specific address.

#### Step 3.3: Confirm Location Before Proceeding

**Tell user:**
```
✅ Delivery address set to: Home - Bohra Layout, Gottigere, Bengaluru
Is this correct?
```

**STOP and wait for confirmation before proceeding to search.**

#### Step 3.4: Handle New Address (if needed)

```bash
openclaw browser snapshot --format aria
openclaw browser type <input-ref> "user's address"
openclaw browser snapshot --format aria
openclaw browser click <suggestion-ref>
```

---

### Phase 4: Restaurant Discovery

#### ⚠️ CRITICAL: Verify Location BEFORE and AFTER Search!

**URL-based search can reset the delivery address.** Always verify the location in the header after navigating.

#### Step 4.1: Search (URL-BASED - PREFERRED METHOD)

**⚠️ USE URL-BASED SEARCH TO AVOID STALE REFS!**

```bash
# URL-based search (PREFERRED - avoids stale refs):
openclaw browser navigate "https://www.swiggy.com/search?query=biryani"
```

Wait 2-3 seconds for results:
```bash
openclaw browser snapshot --format aria
```

#### Step 4.1.1: VERIFY LOCATION AFTER SEARCH (MANDATORY)

**⚠️ CHECK THE HEADER IMMEDIATELY AFTER SEARCH!**

Look at the location in the header. It should show the specific address, NOT just a city name.

**If location is WRONG:**
```bash
# Re-select saved address (DO NOT proceed with wrong location!)
openclaw browser snapshot --format aria
openclaw browser click <location-ref>
openclaw browser snapshot --format aria
# Select the correct saved address
openclaw browser click <home-address-ref>
openclaw browser snapshot --format aria
```

**Only proceed when header shows the correct specific address!**

**FALLBACK: Click-based search (only if URL search fails)**

```bash
openclaw browser snapshot --format aria
openclaw browser click <search-ref>
openclaw browser snapshot --format aria
openclaw browser type <input-ref> "biryani"
openclaw browser press Enter
openclaw browser snapshot --format aria
# VERIFY LOCATION AGAIN after search!
```

#### Step 4.2: Present Options

**Only include data actually visible in snapshot.**

**⚡ SORT BY DELIVERY TIME (FASTEST FIRST) - NOT BY DISTANCE**

Users care about how quickly they'll get their food, not how far away it is.

```
I found these restaurants for "biryani" (sorted by fastest delivery):

1. **Meghana Foods** ⚡ 15-20 min
   ⭐ 4.4 | ₹200 for two

2. **Paradise Biryani** ⚡ 20-25 min
   ⭐ 4.2 | ₹250 for two
   🏷️ 60% off up to ₹120

3. **Behrouz Biryani** ⚡ 30-35 min
   ⭐ 4.1 | ₹400 for two
   🏷️ Free delivery

Which restaurant? (number or name)
Say "more" for additional options.
```

**For more results:**
```bash
openclaw browser press PageDown
openclaw browser snapshot --format aria
```

#### Step 4.3: Wait for Choice

**STOP and wait for user to choose.**

---

### Phase 5: Menu Browsing

#### Step 5.1: Open Restaurant

```bash
openclaw browser snapshot --format aria
openclaw browser click <restaurant-ref>
```

Wait for menu:
```bash
openclaw browser snapshot --format aria
```

**Confirm:**
```
Opening Paradise Biryani...
⭐ 4.2 | 20-25 min | ₹250 for two
```

#### Step 5.2: Show Menu

```
Menu at Paradise Biryani:

📌 **Recommended**
1. Chicken Dum Biryani - ₹279 ⭐ Bestseller
2. Mutton Biryani - ₹379
3. Chicken 65 - ₹189

**Categories:**
• Biryani (8 items)
• Starters (10 items)
• Tandoor (6 items)
• Breads (4 items)

What would you like? Say numbers, names, or ask to see a category.
```

#### Step 5.3: Category Details

If user asks for a category:
```bash
openclaw browser snapshot --format aria
openclaw browser click <category-ref>
openclaw browser snapshot --format aria
```

```
**Starters:**
4. Chicken 65 - ₹189 ⭐ Bestseller
5. Paneer Tikka - ₹169
6. Mutton Seekh Kebab - ₹239
```

---

### Phase 6: Cart Building

#### Step 6.1: Add Items

```bash
openclaw browser snapshot --format aria
openclaw browser click <add-button-ref>
openclaw browser snapshot --format aria
```

**Handle customization popup:**
```
Chicken Biryani options:
- Portion: Half (₹179) / Full (₹279)?
- Add: Raita (+₹40)?
```

Wait for choice:
```bash
openclaw browser snapshot --format aria
openclaw browser click <option-ref>
openclaw browser click <confirm-ref>
```

**Confirm:**
```
✅ Added: Chicken Dum Biryani (Full) - ₹279

Cart: 1 item - ₹279
Add more, or review cart?
```

#### Step 6.2: Cart Modifications

**Remove item:**
```bash
openclaw browser snapshot --format aria
openclaw browser click <cart-ref>
openclaw browser snapshot --format aria
openclaw browser click <remove-ref>
```

**Change quantity:**
```bash
openclaw browser click <plus-or-minus-ref>
```

---

### Phase 7: Checkout Preparation

#### Step 7.1: Review Cart

```bash
openclaw browser snapshot --format aria
openclaw browser click <cart-ref>
openclaw browser snapshot --format aria
```

```
📦 **Your Order from Paradise Biryani**

• 1x Chicken Dum Biryani (Full) - ₹279
• 1x Chicken 65 - ₹189
• 2x Butter Naan - ₹78

Subtotal: ₹546
Delivery fee: ₹25
Taxes: ₹38
─────────────
Total: ₹609

🏷️ 60% off up to ₹120 applied → -₹120
**Final: ₹489**

⏱️ Delivery: 20-25 min

Correct? Say "yes" to proceed or what to change.
```

#### Step 7.2: Offers

```bash
openclaw browser snapshot --format aria
# Look for offers section
```

```
💰 **Available Offers:**
1. SWIGGY60 - 60% off up to ₹120 (Applied ✓)
2. FREEDELIVERY - Free delivery above ₹300
3. SBI15 - 15% off with SBI cards

Try a different offer?
```

#### Step 7.3: Delivery Instructions

```
Special instructions? Examples:
- "Don't ring doorbell"
- "Leave at security"
- "Call on arrival"

Or say "none".
```

---

### Phase 8: Final Checkout

#### Step 8.1: Pre-Payment Summary

```
🛒 **FINAL ORDER SUMMARY**

📍 Delivering to: 123 MG Road, Koramangala
🍽️ Restaurant: Paradise Biryani
⏱️ Delivery: 20-25 min

Items:
• 1x Chicken Dum Biryani - ₹279
• 1x Chicken 65 - ₹189

💰 Total: ₹489 (₹120 discount applied)

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ **PROCEED TO PAYMENT?**

Say "yes" to continue to payment.
Say "change" to modify.
Say "cancel" to abort.
```

**STOP AND WAIT for explicit confirmation.**

#### Step 8.2: Payment

Only after "yes":
```bash
openclaw browser snapshot --format aria
openclaw browser click <checkout-ref>
openclaw browser snapshot --format aria
```

```
💳 **Payment Methods:**

1. Google Pay (UPI)
2. PhonePe
3. Credit/Debit Card
4. Swiggy Money - ₹150 balance
5. Cash on Delivery

Which payment method?
```

```bash
openclaw browser snapshot --format aria
openclaw browser click <payment-ref>
```

#### Step 8.3: Final Payment

```
Payment method selected: Google Pay

⚠️ **FINAL STEP**: The "Pay ₹489" button is ready.

I'll let you complete the payment. Tell me when done!
```

**Only click pay if user explicitly requests:**
```bash
openclaw browser snapshot --format aria
openclaw browser click <pay-ref>
```

---

### Phase 9: Confirmation

```bash
openclaw browser snapshot --format aria
```

```
✅ **ORDER PLACED!**

Order ID: SWG987654321
Restaurant: Paradise Biryani
Delivery: ~25 min (by 7:45 PM)

Track your order on Swiggy app.
Keep browser open for tracking?
```

---

## Error Handling

### Click Failed
```bash
openclaw browser screenshot
openclaw browser snapshot --format aria
# Retry with fresh ref
```

### Page Slow
```
Page loading slowly... waiting...
```
Wait 5 seconds, retry snapshot.

### Unexpected Popup
Find close button and dismiss:
```bash
openclaw browser click <close-ref>
```

### Session Expired
```
Session expired. Please log in again.
I'll wait...
```

### Restaurant Closed
```
⚠️ Paradise Biryani is closed (opens 11 AM).

Find another restaurant?
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
| Key press | `openclaw browser press Enter` / `PageDown` |

---

## Best Practices

1. **Fresh snapshot before every click**
2. **Only report visible data**
3. **User picks everything** - never auto-select
4. **Explicit confirmation for checkout**
5. **Screenshot on errors**
6. **Be transparent** - tell user what's happening
7. **Wait for input** - don't rush
