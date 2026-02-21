---
name: zomato-ordering
description: Order food from Zomato in India via OpenClaw browser automation. Handles restaurant discovery, menu browsing, cart management, offers, and checkout. Never places orders or makes payments without explicit user confirmation.
---

# Zomato Ordering - Production Guide

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

### WHY: The moment you output ANY text, seconds pass. Zomato re-renders. The ref no longer exists.

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

## 📍 LOCATION HANDLING (THE #2 CAUSE OF FAILURE)

### The Problem

**URL navigation (`/bangalore/delivery`) does NOT set the delivery address!**

- URL only sets the CITY (Bangalore, Mumbai, etc.)
- The user's specific address (like "Bohra Layout, Gottigere") must be EXPLICITLY selected
- Location can reset when navigating, searching, or after any page load

### Common Wrong Location Signs

- Header shows just "Bangalore" instead of "Bohra Layout, Gottigere"
- Header shows wrong city (Mumbai, Delhi, "Bandra Kurla Complex")
- Restaurants show 30+ km delivery distances

### The Fix (MANDATORY EVERY TIME)

**After EVERY URL navigation, you MUST:**

1. Take a snapshot and check the location in the header
2. If location is wrong or generic (just city name), click location dropdown
3. Select the user's saved "Home" address
4. Verify the header shows the specific address BEFORE proceeding

**This applies to:**
- Initial page load
- After search URL navigation
- After clicking any link that navigates to a new page
- Any time location looks wrong

### Never Assume Location is Correct!

Even if you just set it, location can reset. ALWAYS verify before presenting restaurants to the user.

---

## 🌐 URL-BASED NAVIGATION (CRITICAL!)

### Why URL-Based Navigation?

Clicking dynamic elements on Zomato causes:
1. **Stale refs** - Elements re-render before click completes
2. **Wrong tab selection** - Lands on "Dining Out" instead of "Delivery"
3. **Language changes** - Clicking wrong elements can trigger location/language changes

**SOLUTION: Use direct URLs instead of clicking tabs/search elements.**

### City URL Slugs

| City | URL Slug |
|------|----------|
| Bangalore | `bangalore` |
| Mumbai | `mumbai` |
| Delhi/NCR | `delhi-ncr` |
| Hyderabad | `hyderabad` |
| Chennai | `chennai` |
| Pune | `pune` |
| Kolkata | `kolkata` |
| Ahmedabad | `ahmedabad` |
| Jaipur | `jaipur` |
| Lucknow | `lucknow` |

### URL Patterns

| Action | URL Pattern |
|--------|-------------|
| Delivery home | `https://www.zomato.com/{city}/delivery` |
| Search | `https://www.zomato.com/{city}/delivery?query={search_term}` |
| Restaurant page | `https://www.zomato.com/{city}/{restaurant-slug}/order` |

### Detecting User's City

1. **Ask user directly**: "Which city are you ordering in?"
2. **From saved address**: Parse location text for city name
3. **Default to Bangalore**: If unsure, use `bangalore` (most common for this user)

### Language/Location Corruption Recovery

If you see Turkish text ("Yemeğe Çık"), German, or other non-English:
1. **DO NOT click anything** - clicking may worsen the issue
2. Navigate directly to the delivery URL: `https://www.zomato.com/bangalore/delivery`
3. The URL-based navigation will reset to correct location

---

## Overview

This skill uses OpenClaw's browser automation to help users order food from Zomato. It handles the complete flow from restaurant discovery to checkout, with full user control at every step.

## Critical Rules

### Rule 1: Fresh Snapshot Before Every Action

Zomato is a dynamic SPA. Element refs (ax1, ax2, etc.) become stale within seconds.

```bash
# ✅ CORRECT - snapshot and click in same turn:
openclaw browser snapshot --format aria
openclaw browser click ax18

# ❌ WRONG - talking/thinking between snapshot and click:
openclaw browser snapshot --format aria  # Got ax18
# "I found the login button at ax18, let me click it..."  <- THIS DELAY CAUSES FAILURE
openclaw browser click ax18  # TimeoutError - ref is stale!
```

**Remember:** The moment you output text or wait, the ref is probably stale. Always click FIRST, then talk.

### Rule 2: Only Report What You Actually See

**NEVER hallucinate or guess data.** If you can't see a price, rating, or distance in the snapshot, don't include it. Say "not shown" or omit the field entirely.

### Rule 3: User Confirms Everything

- User picks the restaurant (show options, wait for choice)
- User picks menu items (show menu, wait for choice)
- User confirms cart before checkout
- User confirms payment method
- **NEVER click "Place Order" or "Pay" without explicit "yes" from user**

### Rule 4: Handle Errors Gracefully

If something fails:
1. Take a screenshot to see what's on screen
2. Take a fresh snapshot
3. Try to understand the current state
4. Either retry or ask user for help

---

## Understanding ARIA Snapshots

When you run `openclaw browser snapshot --format aria`, you get output like:

```
document [ref=ax1]
  banner [ref=ax2]
    link "Zomato" [ref=ax3]
    button "Login" [ref=ax4]
    combobox "Search for restaurant, cuisine or a dish" [ref=ax5]
  main [ref=ax6]
    heading "Inspiration for your first order" [ref=ax7]
    list [ref=ax8]
      listitem [ref=ax9]
        link [ref=ax10]
          img "Paradise Biryani" [ref=ax11]
          text "Paradise Biryani"
          text "4.2"
          text "25-30 min"
          text "₹300 for two"
```

**How to parse this:**
- Look for semantic structure (banner = header, main = content)
- Restaurant cards are usually in `listitem` or `article` elements
- Text content appears after element type
- Use the `ref` values (ax10, ax11, etc.) for clicking

---

## Complete Workflow

### Phase 1: Setup

#### Step 1.1: Start Browser

```bash
openclaw browser start
```

If browser fails to start, check:
```bash
openclaw browser status
```

If stuck, reset:
```bash
openclaw browser stop
openclaw browser start
```

#### Step 1.2: Open Zomato DELIVERY Page (CRITICAL!)

**⚠️ NEVER navigate to `https://www.zomato.com/` directly - it may land on Dining Out!**

**ALWAYS use the direct delivery URL for the user's city:**

```bash
# For Bangalore:
openclaw browser open https://www.zomato.com/bangalore/delivery

# For other cities:
# Mumbai: https://www.zomato.com/mumbai/delivery
# Delhi: https://www.zomato.com/delhi-ncr/delivery
# Hyderabad: https://www.zomato.com/hyderabad/delivery
# Chennai: https://www.zomato.com/chennai/delivery
# Pune: https://www.zomato.com/pune/delivery
# Kolkata: https://www.zomato.com/kolkata/delivery
```

Wait 2-3 seconds for page load, then:

```bash
openclaw browser snapshot --format aria
```

#### Step 1.3: Verify Delivery Tab is Active

**CRITICAL CHECK: Ensure we're on DELIVERY, not Dining Out!**

Look in the snapshot for tab indicators:
- **CORRECT:** "Delivery" tab is selected/active/highlighted
- **WRONG:** "Dining Out" or "Yemeğe Çık" (Turkish) is selected

**If on wrong tab or wrong language detected:**
```bash
# Re-navigate to delivery URL directly - do NOT click tabs
openclaw browser navigate https://www.zomato.com/bangalore/delivery
openclaw browser snapshot --format aria
```

**If language is not English (e.g., Turkish "Yemeğe Çık" instead of "Dining Out"):**
This means location/language got corrupted. Navigate to the delivery page with explicit city:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery
```

If page seems stuck or blank:
```bash
openclaw browser screenshot
```
Check the screenshot, then reload:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery
```

---

### Phase 2: Authentication

#### Step 2.1: Check Login Status

From the snapshot, examine the header area for:

**Logged IN indicators:**
- User's name or profile picture
- "Profile" or account menu
- Cart icon with items count

**Logged OUT indicators:**
- "Login" or "Sign up" button
- "Log in" text in header

#### Step 2.2: Handle Login (AUTOMATIC - don't ask permission)

**If user is NOT logged in, AUTOMATICALLY click the login button:**

```bash
openclaw browser snapshot --format aria
# Find "Login" or "Sign in" button in header
openclaw browser click <login-button-ref>
openclaw browser snapshot --format aria
```

**Tell user (after clicking login):**
```
I've opened the Zomato login popup for you. Please:
1. Enter your phone number
2. Complete the OTP verification
3. Say "done" when logged in

I'll wait for you.
```

**If already logged in, tell user:**
```
You're already logged in to Zomato. Let me proceed to find biryani for you...
```
Then skip to Phase 3.

**STOP AND WAIT for user to say "done" after login.**

After user confirms:
```bash
openclaw browser snapshot --format aria
```

Verify login succeeded by looking for user name/profile in header.

If login failed, click login button again and ask user to retry.

---

### Phase 3: Location Setup (CRITICAL - MUST SELECT SAVED ADDRESS)

#### ⚠️ IMPORTANT: URL Navigation Does NOT Set Delivery Address!

**Problem:** Navigating to `https://www.zomato.com/bangalore/delivery` only sets the CITY (Bangalore).
It does NOT select the user's specific delivery address (like "Home - Bohra Layout, Gottigere").

**Solution:** You MUST explicitly click the location dropdown and select a saved address AFTER URL navigation.

#### Step 3.1: ALWAYS Click Location Dropdown (MANDATORY)

**Even if location looks correct, you MUST verify and select a saved address:**

```bash
openclaw browser snapshot --format aria
# Find location button/dropdown in header (look for text like "Bangalore", "Select location", or an address)
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

Look in the header - it should now show the specific address (e.g., "Bohra Layout, Gottigere"), NOT just "Bangalore".

#### Step 3.3: Confirm Location Before Proceeding

**Tell user:**
```
✅ Delivery address set to: Home - Bohra Layout, Gottigere, Bengaluru
Is this correct?
```

**STOP and wait for confirmation before proceeding to search.**

#### Step 3.4: Handle New Address (if no saved addresses)

**If user wants a different address:**
```bash
openclaw browser snapshot --format aria
openclaw browser type <address-input-ref> "user's address"
openclaw browser snapshot --format aria
# Wait for suggestions
openclaw browser click <suggestion-ref>
```

**Verify and confirm:**
```
Delivery address set to: 123 MG Road, Koramangala, Bangalore 560034
Is this correct?
```

---

### Phase 4: Restaurant Discovery

#### ⚠️ CRITICAL: Verify Location BEFORE and AFTER Search!

**URL-based search can reset the delivery address.** Always verify the location in the header after navigating.

#### Step 4.1: Search for Food (URL-BASED - PREFERRED METHOD)

**⚠️ USE URL-BASED SEARCH TO AVOID STALE REFS!**

Instead of clicking search elements, navigate directly to search results:

```bash
# URL-based search (PREFERRED - avoids stale refs):
openclaw browser navigate "https://www.zomato.com/bangalore/delivery?query=biryani"
```

**URL pattern:** `https://www.zomato.com/{city}/delivery?query={search_term}`

Examples:
- Biryani in Bangalore: `https://www.zomato.com/bangalore/delivery?query=biryani`
- Pizza in Mumbai: `https://www.zomato.com/mumbai/delivery?query=pizza`
- Chinese in Delhi: `https://www.zomato.com/delhi-ncr/delivery?query=chinese`

Wait 2-3 seconds for results:
```bash
openclaw browser snapshot --format aria
```

#### Step 4.1.1: VERIFY LOCATION AFTER SEARCH (MANDATORY)

**⚠️ CHECK THE HEADER IMMEDIATELY AFTER SEARCH URL NAVIGATION!**

Look at the location displayed in the header. It should show:
- ✅ CORRECT: "Bohra Layout, Gottigere" (specific address)
- ❌ WRONG: "Bangalore" (just city name), "Delhi", "Mumbai", or any other location

**If location is WRONG or just shows city name:**
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

If URL-based search doesn't work, use click-based:
```bash
openclaw browser snapshot --format aria
openclaw browser click <search-ref>
openclaw browser snapshot --format aria
openclaw browser type <search-input-ref> "biryani"
openclaw browser press Enter
openclaw browser snapshot --format aria
# VERIFY LOCATION AGAIN after search!
```

#### Step 4.2: Present Restaurant Options

**Parse the snapshot for restaurant information. Only include data you can actually see.**

**⚡ SORT BY DELIVERY TIME (FASTEST FIRST) - NOT BY DISTANCE**

Users care about how quickly they'll get their food, not how far away it is.

Extract from each restaurant card:
- Name (required)
- **Delivery time (PRIMARY - show prominently, like "20-25 min")**
- **Distance (REQUIRED - always include, like "2.1 km")**
- Rating (if shown, usually a number like "4.2")
- Cost for two (if shown, like "₹300 for two")
- Offers (if shown, like "50% off up to ₹100")
- Cuisine types (if shown)

**Present to user SORTED BY FASTEST DELIVERY TIME:**
```
I found these restaurants for "biryani" (sorted by fastest delivery):

1. **Meghana Foods** ⚡ 20-25 min | 2.1 km
   ⭐ 4.4 | ₹250 for two
   Biryani, South Indian

2. **Paradise Biryani** ⚡ 25-30 min | 3.5 km
   ⭐ 4.2 | ₹300 for two
   🏷️ 50% off up to ₹100

3. **Shah Ghouse** ⚡ 30-35 min | 4.2 km
   ⭐ 4.3 | ₹350 for two
   🏷️ Free delivery

4. **Behrouz Biryani** ⚡ 35-40 min | 5.8 km
   ⭐ 4.1 | ₹450 for two

Which restaurant would you like? (say the number or name)
Or say "more" to see additional options.
```

**If user says "more":**
```bash
openclaw browser snapshot --format aria
# Scroll down to load more
openclaw browser press PageDown
openclaw browser snapshot --format aria
```

Then parse and show additional restaurants.

#### Step 4.3: Wait for User Choice

**STOP and wait for user to choose.**

Do NOT auto-select a restaurant. Ever.

---

### Phase 5: Menu Browsing

#### Step 5.1: Open Restaurant

After user chooses:

```bash
openclaw browser snapshot --format aria
# Find the chosen restaurant's link/card
openclaw browser click <restaurant-ref>
```

Wait 2-3 seconds for menu to load:
```bash
openclaw browser snapshot --format aria
```

**Confirm selection:**
```
Opening Paradise Biryani...
⭐ 4.2 rating | 25-30 min delivery | ₹300 for two
Currently OPEN (closes at 11 PM)
```

#### Step 5.2: Show Menu Categories

Parse the menu structure. Zomato typically shows:
- Categories (Biryani, Starters, Breads, etc.)
- Bestseller/Recommended section
- Items with prices

**Present menu overview:**
```
Here's the menu at Paradise Biryani:

📌 **Bestsellers**
1. Chicken Dum Biryani - ₹299 ⭐ Must Try
2. Mutton Biryani - ₹399
3. Chicken 65 - ₹199

**Biryani** (8 items)
**Starters** (12 items)
**Tandoor** (6 items)
**Breads** (5 items)
**Desserts** (4 items)

What would you like to order? Say item numbers, names, or ask to see a specific category.
```

#### Step 5.3: Show Category Details (if requested)

If user says "show starters" or "what's in tandoor":

```bash
openclaw browser snapshot --format aria
# Find category section, may need to scroll
openclaw browser click <category-ref>
openclaw browser snapshot --format aria
```

Parse and show items in that category:
```
**Starters:**
4. Chicken 65 - ₹199 ⭐ Bestseller
5. Paneer Tikka - ₹179
6. Mutton Seekh Kebab - ₹249
7. Fish Fry - ₹229
8. Mushroom Pepper Fry - ₹159 (Veg)
```

#### Step 5.4: Wait for User to Choose Items

**STOP and wait for user to tell you what they want.**

---

### Phase 6: Cart Building

#### Step 6.1: Add Items

For each item the user requests:

```bash
openclaw browser snapshot --format aria
# Find the item's ADD button
openclaw browser click <add-button-ref>
openclaw browser snapshot --format aria
```

**Handle customization popup (if appears):**

Zomato often shows options like:
- Size (Regular/Large)
- Spice level
- Add-ons
- Special instructions

If popup appears:
```
Chicken Dum Biryani has options:
- Size: Regular (₹299) or Large (₹449)?
- Spice: Mild / Medium / Spicy?

What would you prefer?
```

Wait for user choice, then:
```bash
openclaw browser snapshot --format aria
openclaw browser click <option-ref>
openclaw browser click <add-to-cart-ref>
```

**Confirm item added:**
```
✅ Added: Chicken Dum Biryani (Large, Medium spice) - ₹449
```

#### Step 6.2: Continue or Review Cart

After each item:
```
Cart: 1 item - ₹449

Want to add more items, or should I show the full cart?
```

#### Step 6.3: Handle Cart Modifications

**If user wants to remove an item:**
```bash
openclaw browser snapshot --format aria
# Find cart icon
openclaw browser click <cart-ref>
openclaw browser snapshot --format aria
# Find item's remove/minus button
openclaw browser click <remove-ref>
```

**If user wants to change quantity:**
```bash
openclaw browser snapshot --format aria
# Find +/- buttons for the item
openclaw browser click <plus-or-minus-ref>
```

---

### Phase 7: Checkout Preparation

#### Step 7.1: Review Full Cart

```bash
openclaw browser snapshot --format aria
# Open cart if not already open
openclaw browser click <cart-ref>
openclaw browser snapshot --format aria
```

**Parse and present cart details:**
```
📦 **Your Order from Paradise Biryani**

Items:
• 1x Chicken Dum Biryani (Large) - ₹449
• 1x Chicken 65 - ₹199
• 2x Butter Naan - ₹98

Subtotal: ₹746
Delivery fee: ₹30
Taxes: ₹52
─────────────
**Total: ₹828**

🏷️ Offer applied: 50% off up to ₹100 → -₹100
**Final Total: ₹728**

⏱️ Delivery in 25-30 min

Is this correct? Say "yes" to proceed, or tell me what to change.
```

#### Step 7.2: Check for Better Offers

```bash
openclaw browser snapshot --format aria
# Look for "View all offers" or coupon section
```

If offers available:
```
💰 **Available Offers:**
1. WELCOME50 - 50% off up to ₹100 (Applied ✓)
2. FREEDEL - Free delivery on orders above ₹500
3. HDFC20 - 20% off with HDFC cards

Want me to try a different offer?
```

#### Step 7.3: Delivery Instructions

```
Any special delivery instructions? For example:
- "Don't ring the bell"
- "Leave at the door"
- "Call when you arrive"

Or say "none" to skip.
```

If user provides instructions:
```bash
openclaw browser snapshot --format aria
# Find delivery instructions field
openclaw browser click <instructions-ref>
openclaw browser type <input-ref> "user's instructions"
```

---

### Phase 8: Final Confirmation & Checkout

#### Step 8.1: Pre-Checkout Summary

**This is the final checkpoint before payment:**

```
🛒 **FINAL ORDER SUMMARY**

📍 Delivering to: 123 MG Road, Koramangala
🍽️ Restaurant: Paradise Biryani
⏱️ Estimated delivery: 25-30 min

Items:
• 1x Chicken Dum Biryani (Large) - ₹449
• 1x Chicken 65 - ₹199

💰 Total: ₹728 (after ₹100 discount)

📝 Instructions: "Don't ring the bell"

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ **READY TO PROCEED TO PAYMENT?**

Say "yes" or "confirm" to go to payment page.
Say "change" to modify something.
Say "cancel" to abort.
```

**STOP AND WAIT for explicit confirmation.**

Do NOT proceed without user saying yes/confirm/proceed.

#### Step 8.2: Proceed to Payment

Only after user confirms:

```bash
openclaw browser snapshot --format aria
# Find "Proceed to pay" or checkout button
openclaw browser click <checkout-ref>
openclaw browser snapshot --format aria
```

#### Step 8.3: Payment Method Selection

Parse available payment options:
```
💳 **Select Payment Method:**

1. Google Pay (UPI)
2. PhonePe (UPI)
3. Credit/Debit Card
4. Paytm Wallet - ₹250 balance
5. Cash on Delivery (+₹10 fee)

Which payment method do you prefer?
```

Wait for user choice.

```bash
openclaw browser snapshot --format aria
openclaw browser click <payment-method-ref>
```

#### Step 8.4: Final Payment

**Tell user:**
```
I've selected Google Pay as your payment method.

⚠️ **FINAL STEP**: Click the "Pay ₹728" button to complete your order.

I'll let you complete the payment yourself. Let me know once it's done!
```

**Do NOT click the final pay button without explicit permission.**

If user explicitly says "place the order" or "complete payment":
```bash
openclaw browser snapshot --format aria
openclaw browser click <pay-button-ref>
```

---

### Phase 9: Order Confirmation

After payment:
```bash
openclaw browser snapshot --format aria
```

Look for order confirmation:
```
✅ **ORDER PLACED SUCCESSFULLY!**

Order ID: ZMT123456789
Restaurant: Paradise Biryani
Estimated delivery: 7:45 PM (25-30 min)

You can track your order on the Zomato app or website.
Would you like me to keep this browser open for tracking?
```

---

## Error Handling

### Error: Click Failed / Element Not Found

```bash
# Take screenshot to see actual state
openclaw browser screenshot

# Take fresh snapshot
openclaw browser snapshot --format aria

# Try to understand what happened and retry
```

If still failing, tell user:
```
I'm having trouble clicking that element. The page might have changed.
Let me take a screenshot to see what's happening...

[After screenshot]
It looks like [describe what you see].
Should I try again, or would you like to take over?
```

### Error: Page Not Loading

```bash
openclaw browser screenshot
```

```
The page seems to be loading slowly. Let me wait a moment...
```

Wait 5 seconds, then:
```bash
openclaw browser snapshot --format aria
```

If still not loaded:
```
Zomato seems to be slow right now. Should I:
1. Keep waiting
2. Refresh the page
3. Try again later
```

### Error: Unexpected Popup/Modal

```bash
openclaw browser snapshot --format aria
```

Look for modal/popup elements. Try to find close button:
```bash
openclaw browser click <close-ref>
openclaw browser snapshot --format aria
```

If can't close, tell user:
```
There's a popup I can't automatically close. Could you dismiss it in the browser?
```

### Error: Login Required Mid-Flow

If action fails and snapshot shows login prompt:
```
Looks like your session expired. Please log in again.
I'll wait for you to complete the login...
```

### Error: Restaurant Closed/Unavailable

If menu shows "Currently closed" or items unavailable:
```
⚠️ Paradise Biryani is currently closed (opens at 11 AM).

Should I:
1. Find another restaurant serving biryani?
2. Come back later?
```

### Error: Language Changed (Turkish/Other Language)

If you see "Yemeğe Çık" instead of "Dining Out", or any non-English text:

**This is a critical location/language corruption issue!**

1. **DO NOT CLICK ANY ELEMENTS** - this will make it worse
2. Navigate directly to delivery URL:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery
```
3. Wait for page load and verify English text appears
4. If still corrupted, try clearing by opening a fresh URL:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery?query=biryani
```

### Error: Wrong Tab (Dining Out instead of Delivery)

**DO NOT click the Delivery tab!** This causes stale ref issues.

Instead, navigate directly:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery
```

### Error: Location Not Set / Wrong Location (MOST COMMON ISSUE!)

**⚠️ This is the #1 cause of failed orders!** Location resets frequently on Zomato.

**Signs of wrong location:**
- Header shows "Bangalore" instead of specific address like "Bohra Layout, Gottigere"
- Header shows a different city (Mumbai, Delhi, etc.)
- Shows "Bandra Kurla Complex" or other default location
- Restaurant results show unexpected delivery times (30+ km away)

**How to fix (ALWAYS use this sequence):**

1. **DO NOT trust URL navigation alone** - it only sets the city, not the specific address:
```bash
openclaw browser navigate https://www.zomato.com/bangalore/delivery
```

2. **ALWAYS click the location dropdown and select saved address:**
```bash
openclaw browser snapshot --format aria
# Find location button in header
openclaw browser click <location-ref>
openclaw browser snapshot --format aria
```

3. **Select the user's saved "Home" address (or ask which one):**
```bash
openclaw browser snapshot --format aria
# Click the saved address option
openclaw browser click <home-address-ref>
openclaw browser snapshot --format aria
```

4. **Verify the header now shows the specific address** (e.g., "Bohra Layout, Gottigere")

5. **If location keeps resetting, ask user:**
```
The location keeps resetting to Mumbai. This may be due to:
1. Browser cache/cookies from previous sessions
2. Zomato's location detection

Would you like me to:
1. Clear cookies and try again?
2. Let you manually set the location?
```

---

## Command Reference

| Action | Command |
|--------|---------|
| Start browser | `openclaw browser start` |
| Stop browser | `openclaw browser stop` |
| Check status | `openclaw browser status` |
| Open URL | `openclaw browser open <url>` |
| Navigate | `openclaw browser navigate <url>` |
| Get page state | `openclaw browser snapshot --format aria` |
| Take screenshot | `openclaw browser screenshot` |
| Click element | `openclaw browser click <ref>` |
| Type text | `openclaw browser type <ref> "text"` |
| Press key | `openclaw browser press Enter` / `PageDown` / `Escape` |
| Wait for text | `openclaw browser wait --text "text"` |

---

## Best Practices Summary

1. **Always fresh snapshot before any click** - Never reuse old refs
2. **Only report visible data** - Never guess or hallucinate prices/ratings
3. **Present options, don't auto-select** - User picks restaurants, items, everything
4. **Confirm before payment** - Explicit "yes" required for checkout
5. **Handle errors gracefully** - Screenshot, retry, ask user for help
6. **Be transparent** - Tell user what you're doing at each step
7. **Wait for user input** - Don't rush through the flow
8. **Track state** - Remember what's in cart, what's been done
9. **Be CONCISE** - Don't narrate every action. Skip "Let me...", "I'll now...", "I'm going to..."

## ⚡ Output Efficiency Rules

**DO NOT narrate your actions.** Users don't need a play-by-play.

❌ **BAD (verbose):**
```
Let me take a snapshot to see what's on the screen.
Now I'll look for the search results.
I can see several restaurants. Let me parse them for you.
I found 4 restaurants that serve biryani. Here they are:
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
