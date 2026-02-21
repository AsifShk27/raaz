---
name: bigbasket-ordering
description: Order groceries from BigBasket in India via OpenClaw browser automation. Handles product search, cart management, delivery slot selection, and checkout. Never places orders or makes payments without explicit user confirmation.
---

# BigBasket Ordering - Production Guide

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
"I found the add button, let me click it..."   ← ⛔ THIS TEXT OUTPUT MAKES ax18 STALE
openclaw browser click ax18                # FAILS: TimeoutError 8000ms
```

### ✅ CORRECT - This works:

```
openclaw browser snapshot --format aria    # Got ref ax18
openclaw browser click ax18                # Works! Click happens immediately
"I added the item to cart."                # Talk AFTER the click
```

### WHY: The moment you output ANY text, seconds pass. BigBasket re-renders. The ref no longer exists.

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

- Navigating to `https://www.bigbasket.com/` does NOT select user's saved address
- Location can reset when navigating or searching
- Wrong location = items may not be available, delivery slot issues

### Common Wrong Location Signs

- Header shows wrong area or pincode
- Shows "Select your location" prompt
- Items show as unavailable that should be in stock

### The Fix (MANDATORY EVERY TIME)

**After EVERY URL navigation, you MUST:**

1. Take a snapshot and check the location/pincode in the header
2. If location is wrong or shows selection prompt, click location dropdown
3. Select the user's saved address or enter correct pincode
4. Verify the header shows correct address BEFORE proceeding

### Default User Address

For this user, the default delivery address is:
- **Home:** Bohra Layout, Gottigere, Bengaluru 560083

If location shows anything else, it's WRONG and must be fixed.

---

## 🌐 URL-BASED NAVIGATION (CRITICAL!)

### Why URL-Based Navigation?

Clicking dynamic elements on BigBasket causes:
1. **Stale refs** - Elements re-render before click completes
2. **Wrong section** - May land on wrong category
3. **Location changes** - Clicking wrong elements can trigger location popups

**SOLUTION: Use direct URLs instead of clicking elements where possible.**

### URL Patterns

| Action | URL Pattern |
|--------|-------------|
| Home | `https://www.bigbasket.com/` |
| Search | `https://www.bigbasket.com/ps/?q={search_term}` |
| Category | `https://www.bigbasket.com/cl/{category-slug}/` |
| Cart | `https://www.bigbasket.com/basket/` |

### Language/Location Corruption Recovery

If you see unexpected location or wrong city:
1. **DO NOT click random elements**
2. Navigate directly to: `https://www.bigbasket.com/`
3. The location will be prompted - ask user for correct pincode

---

## Overview

This skill uses OpenClaw's browser automation (Playwright-based) to help users order groceries from BigBasket. It handles product search, cart building, slot selection, and checkout with full user control.

## Critical Rules

### Rule 1: Fresh Snapshot Before Every Action

**Click BEFORE talking.** Refs become stale within seconds.

### Rule 2: Only Report What You See

**NEVER guess prices, brands, or availability.** Only show data visible in the snapshot.

### Rule 3: User Confirms Everything

- User picks products from options
- User confirms cart before checkout
- User picks delivery slot
- **NEVER click "Place Order" without explicit "yes"**

### Rule 4: Handle Errors Gracefully

Screenshot → Fresh snapshot → Retry or ask user

---

## Understanding ARIA Snapshots

```
document [ref=ax1]
  banner [ref=ax2]
    link "bigbasket" [ref=ax3]
    searchbox "Search for Products..." [ref=ax4]
    button "Login & Sign Up" [ref=ax5]
  main [ref=ax6]
    article [ref=ax7]
      img "Tata Sampann Toor Dal" [ref=ax8]
      text "Tata Sampann"
      text "Toor Dal"
      text "1 kg"
      text "₹189"
      button "ADD" [ref=ax9]
```

**Key points:**
- Products are usually in `article` elements
- Look for brand, name, size, price as separate text nodes
- "ADD" buttons are clickable refs

---

## Complete Workflow

### Phase 1: Setup

```bash
openclaw browser start
openclaw browser open https://www.bigbasket.com/
```

Wait 2-3 seconds:
```bash
openclaw browser snapshot --format aria
```

**Verify:** BigBasket logo, search bar, categories visible.

---

### Phase 2: Authentication

#### Check Login Status

**Logged IN:** User name, "My Account" with details
**Logged OUT:** "Login & Sign Up" button

#### Handle Login (AUTOMATIC - don't ask permission)

**If user is NOT logged in, AUTOMATICALLY click the login button:**

```bash
openclaw browser snapshot --format aria
# Find "Login & Sign Up" button in header
openclaw browser click <login-ref>
openclaw browser snapshot --format aria
```

**Tell user (after clicking login):**
```
I've opened the BigBasket login popup for you. Please:
1. Enter your phone number
2. Complete OTP verification
3. Say "done" when logged in

I'll wait for you.
```

**If already logged in:**
```
You're already logged in to BigBasket. Let me help you shop...
```
Then skip to Phase 3.

**STOP AND WAIT for user to say "done".**

---

### Phase 3: Location Setup (CRITICAL - MUST SELECT SAVED ADDRESS)

#### ⚠️ IMPORTANT: URL Navigation Does NOT Set Delivery Address!

The location may be wrong even after navigating to BigBasket. You MUST explicitly select a saved address.

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
1. Home - Bohra Layout, Gottigere, Bengaluru 560083
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

Look in the header - it should now show the specific address/pincode.

#### Step 3.3: Confirm Location Before Proceeding

**Tell user:**
```
✅ Delivery address set to: Home - Bohra Layout, Gottigere, Bengaluru 560083
Is this correct?
```

**STOP and wait for confirmation before proceeding to search.**

#### Step 3.4: Handle New Address/Pincode (if needed)

```bash
openclaw browser snapshot --format aria
openclaw browser type <input-ref> "560083"
openclaw browser snapshot --format aria
openclaw browser click <suggestion-ref>
```

---

### Phase 4: Product Search

#### ⚠️ CRITICAL: Verify Location BEFORE and AFTER Search!

**URL-based search can reset the delivery address.** Always verify the location in the header after navigating.

#### Search for Item (URL-BASED - PREFERRED METHOD)

**⚠️ USE URL-BASED SEARCH TO AVOID STALE REFS!**

```bash
# URL-based search (PREFERRED - avoids stale refs):
openclaw browser navigate "https://www.bigbasket.com/ps/?q=toor%20dal"
```

**URL pattern:** `https://www.bigbasket.com/ps/?q={search_term}` (URL-encode spaces as %20)

Wait for results:
```bash
openclaw browser snapshot --format aria
```

#### VERIFY LOCATION AFTER SEARCH (MANDATORY)

**⚠️ CHECK THE HEADER IMMEDIATELY AFTER SEARCH!**

Look at the location/pincode in the header. It should show the correct address.

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
openclaw browser type <input-ref> "toor dal"
openclaw browser press Enter
openclaw browser snapshot --format aria
# VERIFY LOCATION AGAIN after search!
```

#### Present Product Options

**Only show data visible in snapshot:**

```
I found these toor dal options:

1. **Tata Sampann Toor Dal**
   1 kg - ₹189 ⭐ Bestseller

2. **Fortune Arhar Dal**
   1 kg - ₹175

3. **BB Royal Organic Toor Dal**
   1 kg - ₹245 🌿 Organic

4. **Tata Sampann Toor Dal**
   500 g - ₹99

5. **24 Mantra Organic Tur Dal**
   500 g - ₹159 🌿 Organic

Which one would you like? (say the number)
```

**If item out of stock:**
```
⚠️ BB Royal Organic Toor Dal is out of stock.

Alternatives:
1. Tata Sampann Toor Dal - 1kg - ₹189
2. Fortune Arhar Dal - 1kg - ₹175

Would you like one of these instead?
```

#### Wait for User Choice

**STOP and wait for user to pick.**

---

### Phase 5: Cart Building

#### Add Item to Cart

```bash
openclaw browser snapshot --format aria
openclaw browser click <add-button-ref>
```

**Confirm:**
```
✅ Added: Tata Sampann Toor Dal 1kg - ₹189

Basket: 1 item - ₹189
What's next on your list?
```

#### Continue Shopping

For each item user requests:
1. Search for it
2. Show options
3. Wait for choice
4. Add to cart
5. Confirm

```
Current basket:
• Tata Sampann Toor Dal 1kg - ₹189
• Fortune Sunflower Oil 1L - ₹145
• Aashirvaad Atta 5kg - ₹275

Subtotal: ₹609

More items to add, or review basket?
```

#### Handle Quantity Changes

**Increase quantity:**
```bash
openclaw browser snapshot --format aria
openclaw browser click <plus-ref>
```

**Decrease/remove:**
```bash
openclaw browser click <minus-ref>
```

---

### Phase 6: Cart Review

#### View Full Cart

```bash
openclaw browser snapshot --format aria
openclaw browser click <cart-icon-ref>
openclaw browser snapshot --format aria
```

```
🛒 **Your BigBasket Order**

Items:
• 1x Tata Sampann Toor Dal 1kg - ₹189
• 2x Fortune Sunflower Oil 1L - ₹290
• 1x Aashirvaad Atta 5kg - ₹275
• 1x Amul Butter 500g - ₹275
• 3x Britannia Bread - ₹120

Subtotal: ₹1,149
Delivery fee: ₹0 (Free above ₹600)
─────────────
**Total: ₹1,149**

🏷️ Savings: ₹89

Anything to change?
```

#### Apply Offers

```bash
openclaw browser snapshot --format aria
# Look for offers/coupon section
```

```
💰 **Available Offers:**
1. BB10 - 10% off up to ₹150
2. FREEDELIVERY - Free delivery (Already applied ✓)
3. ICICI15 - 15% off with ICICI cards

Try an offer code?
```

---

### Phase 7: Delivery Slot Selection

#### View Available Slots

```bash
openclaw browser snapshot --format aria
openclaw browser click <select-slot-ref>
openclaw browser snapshot --format aria
```

```
📅 **Available Delivery Slots:**

**Tomorrow (Monday, Jan 13)**
1. 6 AM - 9 AM - ₹0
2. 9 AM - 12 PM - ₹0 ⭐ Popular
3. 12 PM - 3 PM - ₹0
4. 3 PM - 6 PM - ₹0
5. 6 PM - 9 PM - ₹29

**Tuesday, Jan 14**
6. 6 AM - 9 AM - ₹0
7. 9 AM - 12 PM - ₹0

Which slot works for you? (say the number)
```

#### Select Slot

```bash
openclaw browser snapshot --format aria
openclaw browser click <slot-ref>
```

```
✅ Slot selected: Tomorrow 9 AM - 12 PM (Free delivery)
```

---

### Phase 8: Checkout

#### Pre-Checkout Summary

```
🛒 **FINAL ORDER SUMMARY**

📍 Delivering to: 123 MG Road, Koramangala
📅 Slot: Tomorrow 9 AM - 12 PM

Items (5):
• 1x Tata Sampann Toor Dal 1kg - ₹189
• 2x Fortune Sunflower Oil 1L - ₹290
• 1x Aashirvaad Atta 5kg - ₹275
• 1x Amul Butter 500g - ₹275
• 3x Britannia Bread - ₹120

💰 Total: ₹1,149
📦 Delivery: Free

━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ **READY TO CHECKOUT?**

Say "yes" to proceed to payment.
Say "change" to modify.
Say "cancel" to abort.
```

**STOP AND WAIT for explicit confirmation.**

#### Proceed to Payment

Only after "yes":
```bash
openclaw browser snapshot --format aria
openclaw browser click <checkout-ref>
openclaw browser snapshot --format aria
```

#### Payment Method Selection

```
💳 **Payment Methods:**

1. Google Pay (UPI)
2. PhonePe (UPI)
3. Credit/Debit Card
4. BB Wallet - ₹50 balance
5. Cash on Delivery

Which payment method?
```

```bash
openclaw browser snapshot --format aria
openclaw browser click <payment-ref>
```

#### Final Payment

```
Payment method: Google Pay

⚠️ **FINAL STEP**: "Pay ₹1,149" button is ready.

I'll let you complete the payment. Tell me when done!
```

**Only click if user explicitly says "place order":**
```bash
openclaw browser snapshot --format aria
openclaw browser click <pay-ref>
```

---

### Phase 9: Order Confirmation

```bash
openclaw browser snapshot --format aria
```

```
✅ **ORDER PLACED!**

Order ID: BB123456789
Items: 5 products
Delivery: Tomorrow 9 AM - 12 PM

You'll receive SMS/email confirmation.
Track at bigbasket.com/my-account/orders

Need anything else?
```

---

## Shopping List Mode

If user provides a list like "I need toor dal, oil, bread, butter":

```
I'll help you find these items:
1. ⬜ Toor dal
2. ⬜ Oil
3. ⬜ Bread
4. ⬜ Butter

Let me start with toor dal...
```

Then for each item:
1. Search
2. Show options
3. Add user's choice
4. Mark complete

```
Progress:
1. ✅ Toor dal - Tata Sampann 1kg - ₹189
2. ✅ Oil - Fortune Sunflower 1L - ₹145
3. ⬜ Bread
4. ⬜ Butter

Searching for bread...
```

---

## Error Handling

### Item Not Found
```
I couldn't find "organic quinoa flakes".

Should I:
1. Try a different search term?
2. Skip this item?
3. Show similar products?
```

### Out of Stock
```
⚠️ Amul Butter 500g is out of stock.

Alternatives:
1. Amul Butter 200g - ₹115
2. Britannia Butter 500g - ₹265
3. Skip this item

Which option?
```

### Click Failed
```bash
openclaw browser screenshot
openclaw browser snapshot --format aria
# Retry
```

### Page Slow
Wait 5 seconds, retry snapshot.

### Session Expired
```
Session expired. Please log in again.
```

### Slot No Longer Available
```
⚠️ The 9 AM - 12 PM slot got booked.

Other available slots:
1. 12 PM - 3 PM - ₹0
2. 3 PM - 6 PM - ₹0

Pick another?
```

---

## Substitution Preferences

Before checkout, ask:
```
If any item is unavailable during packing:
1. Replace with similar item
2. Remove from order (refund)
3. Call me to decide

Which do you prefer?
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
2. **Only report visible data** - never guess prices
3. **Show product options** - user picks, not agent
4. **Track shopping progress** - show checklist for lists
5. **Confirm everything** - especially before payment
6. **Handle out-of-stock gracefully** - offer alternatives
7. **Slot selection is critical** - don't skip it
8. **Ask about substitutions** - before checkout
