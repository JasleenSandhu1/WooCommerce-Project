-- =====================================================================
-- GA4 vs WooCommerce reconciliation (BigQuery Standard SQL)
-- Validated 2026-11-18 against the Phase 5 answer key: 39/39 orders classified correctly.
--
-- Data:
--   GA4 daily export   cascade-analytics-514821.analytics_564395689.events_*   (America/Vancouver)
--   WooCommerce orders cascade-analytics-514821.woo.orders                     (store timezone UTC)
-- Revenue definition: order total incl. tax and shipping in both systems.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Shared CTEs (used by every query below)
-- ---------------------------------------------------------------------
WITH ga4 AS (
  -- One row per transaction_id. purchase_events > 1 = duplicate hits.
  SELECT
    ecommerce.transaction_id                                         AS transaction_id,
    COUNT(*)                                                         AS purchase_events,
    MIN(PARSE_DATE('%Y%m%d', event_date))                            AS ga4_date,        -- Vancouver date
    MAX(ecommerce.purchase_revenue)                                  AS ga4_revenue,     -- counted once per transaction
    SUM(ecommerce.purchase_revenue)                                  AS ga4_revenue_all_hits,
    LOGICAL_OR(COALESCE((SELECT value.int_value FROM UNNEST(event_params)
                         WHERE key = 'debug_mode'), 0) = 1)          AS is_debug         -- sent from GTM Preview
  FROM `cascade-analytics-514821.analytics_564395689.events_*`
  WHERE event_name = 'purchase'
  GROUP BY 1
),
woo AS (
  SELECT
    CAST(order_number AS STRING)                                     AS transaction_id,
    LOWER(REPLACE(order_status, ' ', '-'))                           AS order_status,    -- on-hold, processing, cancelled, refunded
    order_date,
    DATE(order_date)                                                 AS woo_date,        -- UTC date
    CAST(order_total AS FLOAT64)                                     AS order_total,
    CAST(order_refund AS FLOAT64)                                    AS order_refund,
    payment_method, shipping_method, origin,
    origin = 'Web admin'                                             AS is_admin,        -- created in wp-admin, never on the website
    -- GTM container v1 went live ~03:35 UTC Nov 17; earlier web orders were only tracked in Preview (if at all)
    order_date < TIMESTAMP('2026-11-17 03:35:00 UTC')                AS before_tracking_live
  FROM `cascade-analytics-514821.woo.orders`
),
joined AS (
  SELECT
    COALESCE(w.transaction_id, g.transaction_id)                     AS transaction_id,
    CASE WHEN g.transaction_id IS NULL THEN 'woo_only'
         WHEN w.transaction_id IS NULL THEN 'ga4_only'
         ELSE 'matched' END                                          AS match_status,
    w.order_status, w.origin, w.payment_method, w.shipping_method,
    w.is_admin, w.before_tracking_live, w.woo_date, g.ga4_date,
    w.order_total, w.order_refund, g.ga4_revenue, g.ga4_revenue_all_hits, g.purchase_events, g.is_debug,
    ROUND(IFNULL(g.ga4_revenue, 0) - IFNULL(w.order_total, 0), 2)    AS revenue_gap
  FROM woo w
  FULL OUTER JOIN ga4 g USING (transaction_id)
),
classified AS (
  SELECT
    *,
    -- Order of the WHEN clauses = priority when an order has more than one cause
    CASE
      WHEN match_status = 'ga4_only'                                  THEN 'GA4 purchase with no order'
      WHEN match_status = 'woo_only' AND is_admin                     THEN 'Offline / admin order (never on the website)'
      WHEN match_status = 'woo_only' AND before_tracking_live         THEN 'Placed before tracking went live'
      WHEN match_status = 'woo_only'                                  THEN 'Tracking blocked (ad blocker / no GA4 load)'
      WHEN is_debug                                                   THEN 'QA / debug traffic (GTM Preview)'
      WHEN purchase_events > 1                                        THEN 'Duplicate purchase events'
      WHEN order_status IN ('cancelled', 'failed')                    THEN 'Cancelled after purchase'
      WHEN order_status = 'refunded'                                  THEN 'Refunded (no refund event in GA4)'
      WHEN ABS(revenue_gap) > 0.01                                    THEN 'Revenue value mismatch'
      WHEN ga4_date != woo_date                                       THEN 'Date shift (store UTC vs GA4 Vancouver)'
      ELSE 'Clean match'
    END                                                               AS primary_cause,
    (match_status = 'matched' AND ga4_date != woo_date)               AS date_shift_flag,
    (order_status IN ('on-hold', 'pending'))                          AS payment_pending_flag
  FROM joined
)

-- ---------------------------------------------------------------------
-- Q2. Order-level match: one row per order with its primary cause
-- (Q1, Q3, Q4, Q5 below reuse the same CTEs: paste them above each query)
-- ---------------------------------------------------------------------
SELECT transaction_id, match_status, primary_cause, order_status, origin,
       woo_date, ga4_date, order_total, ga4_revenue, revenue_gap, purchase_events,
       is_debug, date_shift_flag, payment_pending_flag
FROM classified
ORDER BY SAFE_CAST(transaction_id AS INT64);

-- ---------------------------------------------------------------------
-- Q1. Volume check
-- ---------------------------------------------------------------------
-- SELECT COUNTIF(match_status != 'ga4_only')          AS woo_orders,
--        COUNTIF(match_status != 'woo_only')          AS ga4_transactions,
--        SUM(IFNULL(purchase_events, 0))              AS ga4_purchase_events,
--        COUNTIF(purchase_events > 1)                 AS ga4_ids_sent_twice
-- FROM classified;

-- ---------------------------------------------------------------------
-- Q3. Summary by cause (the findings table)
-- ---------------------------------------------------------------------
-- SELECT primary_cause, COUNT(*) AS orders,
--        ROUND(SUM(IFNULL(ga4_revenue, 0)), 2)                           AS ga4_revenue,
--        ROUND(SUM(IFNULL(order_total, 0)), 2)                           AS woo_revenue,
--        ROUND(SUM(IFNULL(ga4_revenue, 0)) - SUM(IFNULL(order_total, 0)), 2) AS gap,
--        STRING_AGG(transaction_id, ', ' ORDER BY SAFE_CAST(transaction_id AS INT64)) AS order_ids
-- FROM classified GROUP BY primary_cause ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- Q4. Revenue definitions side by side
-- ---------------------------------------------------------------------
-- SELECT ROUND(SUM(IFNULL(ga4_revenue, 0)), 2)                                    AS ga4_revenue,
--        ROUND(SUM(IF(is_debug, 0, IFNULL(ga4_revenue, 0))), 2)                   AS ga4_revenue_excl_debug,
--        ROUND(SUM(IFNULL(order_total, 0)), 2)                                    AS woo_gross,
--        ROUND(SUM(IF(order_status NOT IN ('cancelled','failed','refunded'), order_total, 0)), 2) AS woo_net
-- FROM classified;

-- ---------------------------------------------------------------------
-- Q5. Match rate (the number to monitor weekly)
-- Web orders placed after tracking went live; admin orders excluded because GA4 can never see them.
-- ---------------------------------------------------------------------
-- SELECT COUNTIF(match_status = 'matched' AND NOT IFNULL(before_tracking_live, FALSE))  AS matched,
--        COUNTIF(NOT IFNULL(is_admin, FALSE) AND NOT IFNULL(before_tracking_live, FALSE)) AS web_orders,
--        ROUND(SAFE_DIVIDE(
--          COUNTIF(match_status = 'matched' AND NOT IFNULL(before_tracking_live, FALSE)),
--          COUNTIF(NOT IFNULL(is_admin, FALSE) AND NOT IFNULL(before_tracking_live, FALSE))) * 100, 1) AS web_match_rate_pct
-- FROM classified;
