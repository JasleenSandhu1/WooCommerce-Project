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

## Known gaps, built in on purpose

- **Refunds don't reach GA4.** Sending refund events needs GTM Kit Premium, so refunded orders keep their revenue in GA4. That's one of the mismatch causes the reconciliation has to find.
- **Ad blockers stop tracking.** Orders placed with an ad blocker are in WooCommerce but not GA4.
- **Phone and admin orders never touch the website,** so GA4 never sees them.
