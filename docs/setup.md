# Setup and decisions

How the store, Tag Manager and GA4 are configured, and why. Several of these choices decide what "revenue" means and where the two systems will disagree, so they're recorded before any data is compared.

## Store (WooCommerce)

| Setting | Value | Why it matters |
|---|---|---|
| Hosting | Local (localhost) | Free and private. GA4 rejects localhost as a stream URL, so the stream uses a placeholder domain. |
| WooCommerce | 11.3, CAD, store in Richmond BC | |
| Site visibility | Live | New stores start in "Coming soon", which hides the shop from guests. Test orders are placed as guests. |
| Store timezone | **UTC** (kept on purpose) | GA4 reports in Vancouver time, so orders after 4 pm Vancouver fall on different dates in each system. |
| Tax | BC 12% (GST + PST), also on shipping | |
| Shipping | Flat rate $7.95; local pickup "Richmond store" ($0) | Feeds `shipping_tier`. |
| Payments | Direct bank transfer, Check payments, Cash on delivery | Bank transfer and check orders wait **on hold** until paid. Feeds `payment_type`. |
| Checkout | Guest checkout allowed | Tracking plugins usually ignore logged-in admins, so test orders are placed as guests. |

## Tag Manager

**GTM Kit** (WordPress plugin) loads the container and writes GA4 ecommerce events to the dataLayer. It's the only thing on the site that loads GTM or GA4, so nothing is counted twice.

| GTM Kit setting | Value | Effect |
|---|---|---|
| WooCommerce tracking | On | Pushes the ecommerce events. |
| Load container on staging/test sites | **On** | GTM Kit otherwise skips sites WordPress reports as local, and Local sites count as local. |
| Exclude tax | Off | `value` includes tax. |
| Exclude shipping | Off | `value` includes shipping. |
| Include customer data | Off | No personal data in the dataLayer. |

**Revenue definition:** GA4 `value` = the full order total, including tax and shipping. The reconciliation uses the same definition on the WooCommerce side.

**GTM container** (`GTM-T6LJLV2J`, published as version `v1 GA4 ecommerce`):

| Item | Configuration |
|---|---|
| Google tag | GA4 measurement ID, trigger *Initialization – All Pages* |
| Variables | Built-in `Event`; Data Layer Variables `DLV - shipping_tier` (`ecommerce.shipping_tier`) and `DLV - payment_type` (`ecommerce.payment_type`) |
| Trigger `CE - GA4 ecommerce` | Custom Event, regex: `^(view_item_list\|select_item\|view_item\|add_to_cart\|remove_from_cart\|view_cart\|begin_checkout\|add_shipping_info\|add_payment_info\|purchase)$` |
| Tag `GA4 - ecommerce events` | GA4 Event, event name `{{Event}}`, *Send Ecommerce data* from the Data Layer, parameters `shipping_tier` and `payment_type` |

One tag with a regex trigger handles all ten events, instead of ten near-identical tags.

## GA4 and BigQuery

| Setting | Value |
|---|---|
| Property | Cascade Demo, timezone America/Vancouver, currency CAD |
| Measurement ID | G-M0K4S1JW4C |
| Custom dimensions | `shipping_tier`, `payment_type` (event scope) |
| BigQuery export | Daily events export; streaming off (sandbox); user data off |
| BigQuery location | northamerica-northeast1 (every dataset in the same region) |

The BigQuery link was created **before** any test orders, because the export only covers data collected after linking.

## Store orders in BigQuery

| Step | How |
|---|---|
| Export | *Advanced Order Export For WooCommerce* plugin, CSV, all statuses (Pending, Processing, On hold, Completed, Cancelled, Refunded) |
| Columns | `order_number`, `order_status`, `order_date` (UTC), `order_total`, `order_tax`, `order_refund`, `order_shipping`, `payment_method`, `shipping_method`, `origin` |
| Table | `woo.orders`, typed columns (order number as integer, date as timestamp, money as numeric) |
| Load check | 39 rows, 39 distinct order numbers, total $1,963.34, statuses match the WooCommerce Orders screen |

The plugin's default status filter only exports Processing and On hold, which silently drops cancelled and refunded orders. Checking the row count against the source caught it.

The raw CSV isn't in this repo: it contains the test customers' names and emails.

## Reporting views and the weekly task

| Item | Configuration |
|---|---|
| Dataset | `reporting`, same region as the GA4 export |
| Views | `reconciliation`, `weekly_kpis`, `weekly_funnel_mix` ([sql/03_reporting_views.sql](../sql/03_reporting_views.sql)) |
| Schedule | Every Monday, a scheduled Claude task reads the three views and drafts the report |
| Week | Last 7 full days in Vancouver time vs the 7 before |
| Match-rate target | 95% |

Details: [weekly-report.md](weekly-report.md)

## Known gaps, built in on purpose

- **Refunds don't reach GA4.** Sending refund events needs GTM Kit Premium, so refunded orders keep their revenue in GA4. That's one of the mismatch causes the reconciliation has to find.
- **Ad blockers stop tracking.** Orders placed with an ad blocker are in WooCommerce but not GA4.
- **Phone and admin orders never touch the website,** so GA4 never sees them.
