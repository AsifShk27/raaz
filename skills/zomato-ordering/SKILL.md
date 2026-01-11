---
name: zomato-ordering
description: Order or manage Zomato food delivery in India via the Clawdbot browser. Use for finding restaurants or dishes, building a cart with item options, applying offers, checking out, and tracking orders. Never place or pay for an order without explicit user confirmation.
---

# Zomato ordering

## Overview

Use the Clawdbot-controlled browser to help the user order food on Zomato: choose location, pick restaurants, add items and modifiers, and track orders. Always ask for confirmation before clicking any final place order or pay action.

## Required inputs

- Delivery location or pickup area
- Order type (delivery or pickup)
- Login method (user completes login or OTP in the browser)
- Restaurant or cuisine preferences and budget
- Item list and item options (size, spice level, add-ons)
- Delivery instructions, tip, and payment preference

## Safety rules

- Never click "Place order", "Pay", or equivalent without explicit user confirmation.
- Do not store credentials, OTPs, or payment details; let the user complete those steps.
- Confirm restaurant, items, modifiers, totals, and ETA before checkout.

## Workflow

1. Start browser and open Zomato
   - `clawdbot browser start`
   - `clawdbot browser open https://www.zomato.com/`
   - Use `clawdbot browser snapshot --format aria` for stable refs.
2. Set location and order type
   - Set delivery location or pickup area using the UI.
   - Ask the user to confirm the selected address.
3. Log in (if required)
   - Ask the user to complete login or OTP in the browser.
   - Resume after login succeeds and a new snapshot confirms the UI.
4. Choose restaurant or search dish
   - Filter by cuisine, rating, or delivery time if requested.
   - Open the restaurant menu and verify serviceability for the address.
5. Build the cart
   - Add items and select required modifiers or add-ons only after user confirmation.
   - Re-snapshot after each modal or menu interaction.
6. Review cart and checkout (confirm first)
   - Verify items, quantities, modifiers, fees, and ETA.
   - Apply offers if requested.
   - Ask for explicit confirmation.
   - Only after confirmation, click the final place order or pay buttons.
   - If payment requires a user step, pause and ask them to finish it.
7. Track order
   - Navigate to order history or tracking page and report ETA or status.

## Troubleshooting

- If the UI shifts or refs go stale, take a fresh `snapshot --format aria`.
- If a modal blocks actions, close it explicitly and re-snapshot.
- If login expires, repeat the login step and confirm the user is re-authenticated.
- If the site shows `ERR_HTTP2_PROTOCOL_ERROR` or fails in headless mode, use non-headless Chrome or a non-snap Chrome build. See `docs/tools/browser-linux-troubleshooting.md`.

## Notes

- Use `docs/tools/browser.md` for the full browser command reference when needed.
