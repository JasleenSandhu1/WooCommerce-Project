# Test orders (the answer key)

Every order in the store was placed on purpose, for a known reason, and logged before any data was compared. The reconciliation is then judged against this log: did the SQL put each order in the right bucket?

**39 orders (#60–#100) and 5 abandoned checkouts, placed Nov 15–17, 2026.** #96 and #97 were skipped: they are hidden drafts WooCommerce creates when you open *Add order* in admin, not orders.

## Scenarios

| Scenario | Orders | Count | How it was created | Expected in GA4 |
|---|---|---|---|---|
| QA runs in GTM Preview | #60, #61, #63 | 3 | Placed while testing the container in Tag Assistant | As debug traffic only (#60 not at all: the Preview session had ended) |
| Before tracking went live | #62 | 1 | Placed before the container was published | No |
| After 4 pm Vancouver | #64–#67 | 4 | Placed in the evening, past midnight UTC | Yes, but on the previous day |
| Normal web orders | #68–#87 | 20 | Guest checkout, a new visitor each time | Yes |
| Thank-you page reloaded | #88–#90 | 3 | Normal order, then the confirmation page refreshed | Yes, once (no duplicate) |
| Cancelled after purchase | #91–#93 | 3 | Bank-transfer orders, cancelled in admin | Yes, with full revenue |
| Refunded | #94, #95 | 2 | Fully refunded in admin | Yes, with full revenue |
| Offline / phone order | #98 | 1 | Created by staff in admin, never on the website | No |
| Tracking blocked | #99, #100 | 2 | Placed in a browser with an ad blocker | No |
| Abandoned checkout | — | 5 | Reached checkout, chose delivery and payment, left | `begin_checkout` with no purchase |

## Mix

- **Delivery:** flat-rate delivery ($7.95) and free pickup at the Richmond store, plus one digital-only order with no shipping.
- **Payment:** direct bank transfer, cheque and cash on delivery. Bank-transfer and cheque orders stay *on hold* until paid.
- **Revenue:** $1,963.34 in total (incl. 12% tax and shipping), of which $110.82 was refunded.

## How the orders were placed

- **As logged-out guests,** like real shoppers. Tracking plugins often skip logged-in admins.
- **A new visitor each time.** GA4 and WooCommerce attribution cookies were cleared and the cart emptied between orders, so each order is a separate GA4 user.
- **Test details only.** Every order uses a made-up name and an `@example.com` address. The raw order export is not published in this repo.
- **Times matter.** The store records in UTC and GA4 in Vancouver time (UTC−8 in November), so each order's time was logged in both.
