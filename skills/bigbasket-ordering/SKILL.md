---
name: bigbasket-ordering
description: Order or manage BigBasket grocery deliveries in India via the Clawdbot browser. Use for searching items, building a cart, selecting delivery slots and addresses, applying offers, checking out, and tracking orders. Never place or pay for an order without explicit user confirmation.
---

# BigBasket ordering

## Overview

Use the Clawdbot-controlled browser to help the user shop on BigBasket: search items, manage the basket, pick address and slot, and track orders. Always ask for confirmation before clicking any final place order or pay action.

## Required inputs

- Delivery location (city or pincode, or a selected saved address)
- Login method (user completes login or OTP in the browser)
- Shopping list (items, brands, sizes, quantities, substitutions)
- Delivery preferences (slot, substitutions, delivery instructions)
- Payment preference (method; user completes payment if required)

## Safety rules

- Never click "Place order", "Pay", or equivalent without explicit user confirmation.
- Do not store credentials, OTPs, or payment details; let the user complete those steps.
- Read back the cart summary (items, quantities, totals, slot) before checkout.

## Workflow

1. Start browser and open BigBasket
   - `clawdbot browser start`
   - `clawdbot browser open https://www.bigbasket.com/`
   - Use `clawdbot browser snapshot --format aria` for stable refs.
2. Set location or address
   - Use the UI to set delivery location or address.
   - If a saved address list appears, ask the user which one to use.
3. Log in (if required)
   - Ask the user to complete login or OTP in the browser.
   - Resume after login succeeds and a new snapshot confirms the UI.
4. Build the basket
   - Search for each item, open product details, confirm pack size, add to cart.
   - If an item is out of stock, propose alternatives and ask before adding.
   - Re-snapshot after each navigation or modal change.
5. Review cart and slot
   - Open the cart, verify quantities and prices, and apply offers if requested.
   - Select or confirm a delivery slot and replacement preferences.
6. Checkout (confirm first)
   - Summarize the order total and slot.
   - Ask for explicit confirmation.
   - Only after confirmation, click the final place order or pay buttons.
   - If payment requires a user step, pause and ask them to finish it.
7. Track order
   - Navigate to order history or tracking page and report ETA or status.

## Troubleshooting

- If the UI shifts or refs go stale, take a fresh `snapshot --format aria`.
- If a modal blocks actions, close it explicitly and re-snapshot.
- If login expires, repeat the login step and confirm the user is re-authenticated.

## Notes

- Use `docs/tools/browser.md` for the full browser command reference when needed.
