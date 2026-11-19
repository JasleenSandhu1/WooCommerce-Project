# Weekly GA4 report (Phase 8)

A one-page monitoring report that writes itself every Monday: how the store did last week, where shoppers dropped off, and whether the tracking can be trusted.

## How it runs

```
GA4 daily export ──► BigQuery views (reporting.*) ──► scheduled AI task (Mondays) ──► one-page report, marked DRAFT
WooCommerce orders ─┘
```

1. **BigQuery views** hold all the logic (`sql/03_reporting_views.sql`):
   - `reporting.weekly_kpis`: the last 7 full days (Vancouver time) vs the 7 before.
   - `reporting.weekly_funnel_mix`: funnel steps, delivery mix and payment mix.
   - `reporting.reconciliation`: the GA4-vs-orders match from Phase 7.
2. **A scheduled Claude task** runs every Monday. It only runs `SELECT *` on the three views, so the numbers always come from the validated SQL, never from the AI's own arithmetic.
3. **The output is a draft.** The report is marked DRAFT for an analyst to check before it goes to anyone.

## What's in it

| Section | Contents |
|---|---|
| Headline KPIs | Sessions, users, orders, revenue, conversion rate and AOV, each vs the previous week |
| Funnel | Users at each step from product view to purchase, and the biggest drop |
| Delivery and payment mix | Pickup vs delivery, and payment methods, per order |
| Data quality | Match rate vs the 95% target with the causes of any gap, duplicate purchases, purchases with no ID, QA traffic excluded |
| Summary | Three plain-language bullets |

## First run: Nov 11–17, 2026

| KPI | Value |
|---|---|
| Sessions | 36 |
| Orders | 32 |
| Revenue | $1,650.98 |
| Conversion rate | 88.9% |
| AOV | $51.59 |
| Match rate | **94.1%** (below the 95% target: 2 ad-blocked orders) |

- **Funnel:** 34 shoppers started checkout and 29 purchased; all 5 drop-offs are the planned abandoned checkouts.
- **Mix:** 17 flat-rate delivery, 14 pickup, 1 digital-only. Payment split evenly: 11 cash on delivery, 11 bank transfer, 10 cheque.
- **Data quality:** no duplicate purchases, no purchases without an ID, and GTM Preview traffic left out.

*The conversion rate is unrealistically high because every test visitor was sent to buy. There's no previous week to compare against yet.*

## Design choices

- **QA traffic is excluded** (`debug_mode` = 1), so testing doesn't inflate the KPIs.
- **Orders are counted once per transaction ID,** so a duplicate hit can't double the revenue. Duplicates are reported as a data-quality issue instead.
- **The funnel can't split checkout drop-off by step.** GTM Kit only sends the shipping and payment events when the order is placed, so every abandonment shows up right after `begin_checkout` ([QA report](tracking-qa.md)).
- **Store data refreshes only on export.** If the order table hasn't been updated that week, the report says the match rate is "not refreshed" instead of showing 0%.
