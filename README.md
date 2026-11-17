# Why GA4 and the store never agree on revenue

**A tracked WooCommerce store, with the real-world causes of GA4-vs-orders mismatch planted on purpose, and the QA and SQL needed to explain every gap.**

`Google Tag Manager` · `GA4` · `BigQuery` · `SQL` · `WooCommerce` · `GTM Kit`

---

## The problem

Every ecommerce team hits the same question: *GA4 says one revenue number, the order system says another. Which is right, and why?* The answer is rarely "tracking is broken". It's a mix of ad blockers, phone orders, cancellations, refunds, test traffic and timezones. Each one is invisible until someone looks for it.

To study this with a known answer, I built a store where I control every order. Each cause of mismatch is placed on purpose and logged, so the reconciliation can be checked against an answer key.

## What I built

```
WooCommerce store ──► GTM Kit (dataLayer) ──► Google Tag Manager ──► GA4 ──► BigQuery
        │                                                                     ▲
        └─────────────────────── orders (UTC) ────────────────────────────────┘
```

- **Tracking:** 10 GA4 ecommerce events, from product list to purchase, sent through **one** GTM tag with a regex trigger. Two custom dimensions record **pickup vs. delivery** and **payment method**.
- **QA:** tested at three layers: the dataLayer, GTM Preview and GA4 itself (DebugView and raw network hits).
- **Test orders:** about 38 orders. Normal web orders sit alongside blocked tracking, phone orders, cancellations, refunds, abandoned checkouts and orders that cross midnight UTC.
- **Reconciliation:** SQL in BigQuery joins GA4 purchases to orders by `transaction_id` and labels every gap with its cause.

## Key findings so far

**1. GA4 silently drops products on two checkout steps.**
GTM Kit sends the product list on `add_shipping_info` and `add_payment_info` as an object, not an array, and GA4 discards it. Event counts and revenue are unaffected, so nothing looks wrong in standard reports. Only a QA check of the raw hits caught it. → [QA report](docs/tracking-qa.md)

**2. Abandoned checkouts can't be split into shipping vs. payment drop-off.**
Both checkout events fire only when the order is placed. So in GA4's funnel, every abandonment happens right after `begin_checkout`. That's a measurement gap worth knowing before anyone acts on a funnel report.

**3. QA traffic leaks into store attribution.**
WooCommerce recorded orders from GTM Preview as *Referral: tagassistant.google.com*. Left in, these would inflate one "channel" and add orders GA4 never counted as real traffic. The same label makes them easy to exclude.

**4. The same order can fall on two different days.**
The store records in UTC and GA4 reports in Vancouver time. Every order placed after 4 pm Pacific lands on the next day in the store, so daily totals disagree even when every order is tracked.

*Reconciliation results will be added once all test orders have been exported.*

## Setup decisions that shape the numbers

| Decision | Choice | Effect on the comparison |
|---|---|---|
| Revenue definition | Order total **incl. tax and shipping** | Both systems are compared like for like |
| Store timezone | UTC (GA4: America/Vancouver) | Creates the date-boundary mismatch above |
| Refund tracking | Not sent to GA4 (needs GTM Kit Premium) | Refunded orders keep their revenue in GA4 |
| Test orders | Placed as logged-out guests | Matches real shoppers; admin sessions are often excluded from tracking |
| BigQuery link | Created before any orders | The export only covers data collected after linking |

Full configuration: [docs/setup.md](docs/setup.md)

## Limitations

- The store runs locally with test orders, so the volumes are small. The point is to show the method and every known cause of mismatch, not real-world proportions.
- GA4 data in BigQuery arrives once a day (sandbox, no streaming), so the reconciliation always runs on the previous day's data.

## What's in this repo

| Path | Contents |
|---|---|
| [`docs/tracking-qa.md`](docs/tracking-qa.md) | QA method, results table and known limitations |
| [`docs/setup.md`](docs/setup.md) | Store, GTM and GA4 configuration, and the reasoning behind it |
| `gtm/` | Exported GTM container (importable into any GTM account) |
| `screenshots/` | Tag Assistant, DebugView and order evidence |
