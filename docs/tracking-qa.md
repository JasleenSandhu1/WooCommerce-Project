# Tracking QA (Phase 4)

**Result: passed on Nov 16, 2026, with one known limitation and one privacy finding.** Every ecommerce event fires once, at the right step, and reaches GA4 with correct values. `add_shipping_info` and `add_payment_info` arrive without their product list. The Google tag also has automatic user-provided data collection switched on, which is documented below and left as is in this demo.

## Method

Three independent checks, each covering what the others can't see:

| Layer | Tool | What it proves |
|---|---|---|
| dataLayer | Browser console, reading `window.dataLayer` after every step | GTM Kit sends the right events with the right values. |
| Tag Manager | GTM Preview / Tag Assistant (Incognito) | The GA4 tag fires on each event and the variables resolve. |
| GA4 | DebugView, then the raw `g/collect` requests after publishing | GA4 receives each event once, with parameters and items. |

Each run was a full guest journey: Shop → product page → Add to cart → Cart → Checkout → choose delivery and payment → Place order → reload the thank-you page. Runs covered both delivery methods (Flat rate, Pickup) and all three payment methods.

## Results

| Check | Passes when | Result |
|---|---|---|
| Container loads | Tag Assistant shows GTM-T6LJLV2J with destination G-M0K4S1JW4C on every page | ✅ |
| Events fire once, at the right moment | Each event appears once, at the matching step | ✅ |
| GA4 tag fires on each event | `GA4 - ecommerce events` under *Tags Fired* | ✅ |
| Purchase is complete | `transaction_id` = order number; `value`, `tax`, `shipping`, `currency` CAD and `items` present | ✅ |
| No duplicate purchase | Reloading the thank-you page sends no second `purchase` | ✅ |
| Custom parameters arrive | `shipping_tier` and `payment_type` show the chosen values | ✅ |
| GA4 receives it | Events and parameters visible in DebugView | ✅ |
| One hit per event | Each event appears in exactly one GA4 request (no double-loaded GA4) | ✅ |
| Value matches the definition | `value` = order total incl. tax and shipping | ✅ e.g. order #65: $55.00 + $7.95 + 12% tax = $70.50 |
| Items on every event | Product list present on all ecommerce events | ⚠️ missing on 2 events (below) |

## Known limitation: no items on two checkout events

**What:** `add_shipping_info` and `add_payment_info` reach GA4 with no product details. All other events, including `purchase`, carry them.

**Why:** GTM Kit pushes `ecommerce.items` on those two events as an object (`{"0": {...}}`) instead of an array (`[{...}]`). GA4 only reads arrays, so it drops the list.

**Evidence:** the dataLayer shows the object; DebugView shows no Items tab on those two events; the raw GA4 requests carry no `pr1` item parameter for them.

**Impact:** small. Funnel step counts, revenue and product sales (from `purchase`) are complete. Only the per-product breakdown at the shipping and payment steps is missing.

**Possible fix (not applied):** a Custom JavaScript variable in GTM that converts the object to an array, used as the items source on those two events.

## Privacy finding: automatic user-provided data collection is on

**What:** the exported container shows the Google tag's **automatic user-provided data collection** switched on, with email, phone and address detection all enabled. It's a Google tag setting, separate from GTM Kit's *Include customer data* option, which is off.

**What it does:** the Google tag can detect personal details a shopper types into forms, such as the checkout email, and send them to Google in hashed form. That is used for features like enhanced conversions.

**Decision for this project:** left as is. The store only takes test orders with made-up `@example.com` addresses, so no real personal data is collected, and the published container (`gtm/GTM-T6LJLV2J_v1.json`) shows the setting exactly as it was tested.

**For a live store:** this would need a privacy and consent review before launch, covering whether the privacy notice discloses it and whether consent is required under Canadian privacy law (PIPEDA, and provincial laws such as BC's PIPA). Unless there is a clear purpose and consent, the default should be to switch it off in the Google tag (*Configuration settings → Include user-provided data from your website*).

## Other findings

- **Parameter values are WooCommerce codes, not labels.** `shipping_tier` arrives as `flat_rate:1` or `pickup_location:0`, and `payment_type` as `bacs`, `cheque` or `cod`. Reports need a lookup to show readable names.
- **Digital-only orders skip delivery.** An order with only a downloadable product sends `add_shipping_info` with an empty `shipping_tier`.
- **Checkout events fire on "Place order".** GTM Kit sends `add_shipping_info` and `add_payment_info` only when the order is submitted. So an abandoned checkout shows `begin_checkout` and nothing after it: the funnel can't show whether shoppers dropped at the shipping or the payment step.
- **`add_to_cart` fires on the click,** even if adding the item then fails, so GA4 can slightly over-count add-to-carts.
- **Item prices include tax** (a $16.00 cap is sent as 17.92), consistent with the tax-inclusive revenue definition.
- **An ad blocker stops GA4 completely.** For the two ad-blocked test orders, GA4 recorded no events at all, not even page views.
- **QA traffic shows up in store attribution, and the label sticks.** WooCommerce recorded orders placed during GTM Preview as *Referral: tagassistant.google.com*. Two later orders placed directly in the same browser inherited that label, because WooCommerce's attribution keeps the last referral and a direct visit doesn't overwrite it. So the reconciliation identifies test orders by GA4's debug flag and by the container's publish time, not by order origin.
- **GA4 enhanced measurement** adds `page_view`, `scroll`, `form_start`, `form_submit` and `user_engagement` outside the GTM tag. These are expected and are not part of the ecommerce reconciliation.

## Troubleshooting notes

- **Tag Assistant wouldn't connect in normal Chrome.** An ad-blocking extension blocked `gtm.js`, so QA was run in Incognito. The same blocker is used on purpose later for the "tracking blocked" test orders.
- **"Google tag GTM-T6LJLV2J not found" before publishing.** This is expected: an unpublished container only loads in Preview mode.
- **An order missing from DebugView** had been placed after Tag Assistant showed "Not connected". Outside Preview, the unpublished container sends nothing.
