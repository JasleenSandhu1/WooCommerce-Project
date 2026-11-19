# Why GA4 and the store never agree on revenue

**A tracked WooCommerce store, with the real-world causes of GA4-vs-orders mismatch planted on purpose, and the QA and SQL needed to explain every gap.**

`Google Tag Manager` · `GA4` · `BigQuery` · `SQL` · `WooCommerce` · `GTM Kit`

---

## The problem

Every ecommerce team hits the same question: *GA4 says one revenue number, the order system says another. Which is right, and why?* The answer is rarely "tracking is broken". It's a mix of ad blockers, phone orders, cancellations, refunds, test traffic and timezones. Each one is invisible until someone looks for it.

To study this with a known answer, I built a store where I control every order. Each cause of mismatch is placed on purpose and logged, so the reconciliation can be checked against an answer key.

## What I built

```
WooCommerce store ──► GTM Kit (dataLayer) ──► Google Tag Manager ──► GA4 ──► BigQuery ──► weekly report
        │                                                                     ▲
        └─────────────────────── orders (UTC) ────────────────────────────────┘
```

- **Tracking:** 10 GA4 ecommerce events, from product list to purchase, sent through **one** GTM tag with a regex trigger. Two custom dimensions record **pickup vs. delivery** and **payment method**.
- **QA:** tested at three layers: the dataLayer, GTM Preview and GA4 itself (DebugView and raw network hits).
- **Test orders:** 39 orders and 5 abandoned checkouts. Normal web orders sit alongside blocked tracking, a phone order, cancellations, refunds and orders that cross midnight UTC. → [answer key](docs/test-orders.md)
- **Reconciliation:** SQL in BigQuery joins GA4 purchases to orders by `transaction_id` and labels every gap with its cause.
- **Weekly report:** BigQuery views feed a scheduled task that drafts a one-page GA4 report every Monday, including the match rate. → [how it works](docs/weekly-report.md)

## Result

**The SQL explained all 39 orders and matched the answer key 39/39.** GA4 recorded $1,718.18; the store, $1,963.34.

| Cause | Orders | Effect on GA4 |
|---|---|---|
| Clean match | 23 | — |
| Date shift (after 4 pm Vancouver) | 4 | Right total, wrong day |
| Cancelled or refunded | 5 | **+$224.94** kept as revenue |
| Ad blocker | 2 | **−$180.26** never recorded |
| Before tracking went live | 2 | −$46.98 never recorded |
| Phone / admin order | 1 | −$17.92 never recorded |
| QA traffic (GTM Preview) | 2 | Recorded, flagged as debug |

**Match rate: 94.1%** (32 of 34 website orders after go-live), just under a typical 95% target. → [full results](docs/reconciliation-results.md)

## Key findings

**1. GA4 silently drops products on two checkout steps.**
GTM Kit sends the product list on `add_shipping_info` and `add_payment_info` as an object, not an array, and GA4 discards it. Event counts and revenue are unaffected, so nothing looks wrong in standard reports. Only a QA check of the raw hits caught it. → [QA report](docs/tracking-qa.md)

**2. Abandoned checkouts can't be split into shipping vs. payment drop-off.**
Both checkout events fire only when the order is placed. So in GA4's funnel, every abandonment happens right after `begin_checkout`. That's a measurement gap worth knowing before anyone acts on a funnel report.

**3. QA traffic leaks into store attribution.**
WooCommerce recorded orders from GTM Preview as *Referral: tagassistant.google.com*. Left in, these would inflate one "channel" and add orders GA4 never counted as real traffic. The label also sticks: two later orders from the same browser inherited it, so it can't be used on its own to exclude test orders.

**4. The same order can fall on two different days.**
The store records in UTC and GA4 reports in Vancouver time. Every order placed after 4 pm Pacific lands on the next day in the store, so daily totals disagree even when every order is tracked.

**5. A near-perfect total can hide two large errors.**
GA4 was only $20.22 (1.2%) off store net sales. But that was $224.94 of cancelled and refunded orders GA4 still counted, offset by $245.16 of orders it never saw. Only an order-level match shows both. → [reconciliation](docs/reconciliation-results.md)

**6. The Google tag collects user-provided data by default.**
The container has automatic user-provided data collection switched on (hashed email, phone, address). It's harmless with test data, but a live Canadian store would need a privacy and consent review first. → [QA report](docs/tracking-qa.md#privacy-finding-automatic-user-provided-data-collection-is-on)

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
- Store orders reach BigQuery through a manual CSV export, so the weekly match rate is only as fresh as the last upload.
- The weekly report is drafted by an AI task from fixed SQL views and marked DRAFT for review.

## What's in this repo

| Path | Contents |
|---|---|
| [`docs/setup.md`](docs/setup.md) | Store, GTM, GA4 and BigQuery configuration, and the reasoning behind it |
| [`docs/tracking-qa.md`](docs/tracking-qa.md) | QA method, results, known limitation and privacy finding |
| [`docs/test-orders.md`](docs/test-orders.md) | Every test scenario and its order numbers (the answer key) |
| [`docs/reconciliation-results.md`](docs/reconciliation-results.md) | GA4 vs orders: every gap, its cause and the match rate |
| [`docs/weekly-report.md`](docs/weekly-report.md) | The automated weekly GA4 report and its first run |
| [`sql/`](sql) | Reconciliation query, weekly report queries, and the BigQuery views |
| [`gtm/`](gtm) | Exported GTM container (importable into any GTM account) |
| [`screenshots/`](screenshots) | GTM, Tag Assistant, GA4 and order evidence |
