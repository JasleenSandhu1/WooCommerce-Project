-- =====================================================================
-- Saved views used by the weekly scheduled report (BigQuery Standard SQL)
-- Dataset: cascade-analytics-514821.reporting  (northamerica-northeast1)
--
--   reporting.reconciliation     = sql/01_reconciliation.sql, one row per order / transaction
--   reporting.weekly_kpis        = R1 of sql/02_weekly_ga4_report.sql
--   reporting.weekly_funnel_mix  = R2 + R3 of sql/02_weekly_ga4_report.sql
--
-- The scheduled task only runs SELECT * on these views, so the logic lives
-- in one place and the report can't drift from the validated SQL.
-- Definitions below match the deployed views (INFORMATION_SCHEMA.VIEWS, 2026-11-18).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS `cascade-analytics-514821.reporting`
  OPTIONS (location = 'northamerica-northeast1');

-- ---------------------------------------------------------------------
-- 1. reporting.reconciliation
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `cascade-analytics-514821.reporting.reconciliation` AS
WITH ga4 AS (
  SELECT ecommerce.transaction_id AS transaction_id, COUNT(*) AS purchase_events,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS ga4_date, MAX(ecommerce.purchase_revenue) AS ga4_revenue,
    SUM(ecommerce.purchase_revenue) AS ga4_revenue_all_hits,
    LOGICAL_OR(COALESCE((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'debug_mode'), 0) = 1) AS is_debug
  FROM `cascade-analytics-514821.analytics_564395689.events_*` WHERE event_name = 'purchase' GROUP BY 1
),
woo AS (
  SELECT CAST(order_number AS STRING) AS transaction_id, LOWER(REPLACE(order_status, ' ', '-')) AS order_status,
    order_date, DATE(order_date) AS woo_date, CAST(order_total AS FLOAT64) AS order_total, CAST(order_refund AS FLOAT64) AS order_refund,
    payment_method, shipping_method, origin, origin = 'Web admin' AS is_admin,
    order_date < TIMESTAMP('2026-11-17 03:35:00 UTC') AS before_tracking_live   -- GTM container v1 published
  FROM `cascade-analytics-514821.woo.orders`
),
joined AS (
  SELECT COALESCE(w.transaction_id, g.transaction_id) AS transaction_id,
    CASE WHEN g.transaction_id IS NULL THEN 'woo_only' WHEN w.transaction_id IS NULL THEN 'ga4_only' ELSE 'matched' END AS match_status,
    w.order_status, w.origin, w.payment_method, w.shipping_method, w.is_admin, w.before_tracking_live,
    w.order_date, w.woo_date, g.ga4_date, w.order_total, w.order_refund, g.ga4_revenue, g.ga4_revenue_all_hits, g.purchase_events, g.is_debug,
    ROUND(IFNULL(g.ga4_revenue, 0) - IFNULL(w.order_total, 0), 2) AS revenue_gap
  FROM woo w FULL OUTER JOIN ga4 g USING (transaction_id)
)
SELECT *,
  CASE
    WHEN match_status = 'ga4_only' THEN 'GA4 purchase with no order'
    WHEN match_status = 'woo_only' AND is_admin THEN 'Offline / admin order (never on the website)'
    WHEN match_status = 'woo_only' AND before_tracking_live THEN 'Placed before tracking went live'
    WHEN match_status = 'woo_only' THEN 'Tracking blocked (ad blocker / no GA4 load)'
    WHEN is_debug THEN 'QA / debug traffic (GTM Preview)'
    WHEN purchase_events > 1 THEN 'Duplicate purchase events'
    WHEN order_status IN ('cancelled', 'failed') THEN 'Cancelled after purchase'
    WHEN order_status = 'refunded' THEN 'Refunded (no refund event in GA4)'
    WHEN ABS(revenue_gap) > 0.01 THEN 'Revenue value mismatch'
    WHEN ga4_date != woo_date THEN 'Date shift (store UTC vs GA4 Vancouver)'
    ELSE 'Clean match'
  END AS primary_cause,
  (match_status = 'matched' AND ga4_date != woo_date) AS date_shift_flag,
  (order_status IN ('on-hold', 'pending')) AS payment_pending_flag
FROM joined;

-- ---------------------------------------------------------------------
-- 2. reporting.weekly_kpis  (last 7 full Vancouver days vs the 7 before; debug traffic excluded)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `cascade-analytics-514821.reporting.weekly_kpis` AS
WITH params AS (SELECT DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 1 DAY) AS this_end),
p AS (SELECT this_end, DATE_SUB(this_end, INTERVAL 6 DAY) AS this_start, DATE_SUB(this_end, INTERVAL 13 DAY) AS prev_start FROM params),
ev AS (
  SELECT IF(PARSE_DATE('%Y%m%d', e.event_date) >= p.this_start, 'this_week', 'prev_week') AS period,
    e.event_name, e.user_pseudo_id,
    CONCAT(e.user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS STRING)) AS session_key,
    NULLIF(NULLIF(e.ecommerce.transaction_id, ''), '(not set)') AS transaction_id,
    e.ecommerce.purchase_revenue AS revenue,
    COALESCE((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'debug_mode'), 0) = 1 AS is_debug
  FROM `cascade-analytics-514821.analytics_564395689.events_*` e, p
  WHERE e._TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', p.prev_start) AND FORMAT_DATE('%Y%m%d', p.this_end)
),
clean AS (SELECT * FROM ev WHERE NOT is_debug),
purchases AS (SELECT period, transaction_id, MAX(revenue) AS revenue, COUNT(*) AS hits FROM clean WHERE event_name = 'purchase' AND transaction_id IS NOT NULL GROUP BY 1, 2),
periods AS (SELECT 'this_week' AS period UNION ALL SELECT 'prev_week'),
traffic AS (SELECT period, COUNT(DISTINCT session_key) AS sessions, COUNT(DISTINCT user_pseudo_id) AS users FROM clean GROUP BY 1),
sales AS (SELECT period, COUNT(*) AS orders, ROUND(SUM(revenue), 2) AS revenue_cad, COUNTIF(hits > 1) AS duplicate_ids FROM purchases GROUP BY 1),
dq AS (SELECT period, COUNTIF(event_name = 'purchase' AND transaction_id IS NULL) AS purchases_missing_id, COUNTIF(is_debug) AS debug_events_excluded FROM ev GROUP BY 1)
SELECT pr.period,
  (SELECT IF(pr.period = 'this_week', this_start, prev_start) FROM p) AS start_date,
  (SELECT IF(pr.period = 'this_week', this_end, DATE_SUB(this_start, INTERVAL 1 DAY)) FROM p) AS end_date,
  IFNULL(t.sessions, 0) AS sessions, IFNULL(t.users, 0) AS users, IFNULL(s.orders, 0) AS orders, IFNULL(s.revenue_cad, 0) AS revenue_cad,
  ROUND(SAFE_DIVIDE(s.orders, t.sessions) * 100, 2) AS conversion_rate_pct, ROUND(SAFE_DIVIDE(s.revenue_cad, s.orders), 2) AS aov_cad,
  IFNULL(s.duplicate_ids, 0) AS duplicate_ids, IFNULL(dq.purchases_missing_id, 0) AS purchases_missing_id, IFNULL(dq.debug_events_excluded, 0) AS debug_events_excluded
FROM periods pr LEFT JOIN traffic t USING (period) LEFT JOIN sales s USING (period) LEFT JOIN dq USING (period);

-- ---------------------------------------------------------------------
-- 3. reporting.weekly_funnel_mix  (funnel by step + delivery and payment mix, last 7 full days)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `cascade-analytics-514821.reporting.weekly_funnel_mix` AS
WITH p AS (SELECT DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 1 DAY) AS this_end, DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 7 DAY) AS this_start),
ev AS (
  SELECT e.event_name, e.user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'shipping_tier') AS shipping_tier,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'payment_type') AS payment_type
  FROM `cascade-analytics-514821.analytics_564395689.events_*` e, p
  WHERE e._TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', p.this_start) AND FORMAT_DATE('%Y%m%d', p.this_end)
    AND COALESCE((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'debug_mode'), 0) = 0
),
steps AS (SELECT * FROM UNNEST([STRUCT(1 AS step_order, 'view_item' AS step), (2, 'add_to_cart'), (3, 'begin_checkout'), (4, 'add_shipping_info'), (5, 'add_payment_info'), (6, 'purchase')])),
funnel AS (SELECT s.step_order, s.step, COUNT(DISTINCT ev.user_pseudo_id) AS users, COUNT(ev.event_name) AS events FROM steps s LEFT JOIN ev ON ev.event_name = s.step GROUP BY 1, 2)
SELECT 'R2 funnel' AS section, step_order AS sort, step AS label, users, events, ROUND(SAFE_DIVIDE(users, LAG(users) OVER (ORDER BY step_order)) * 100, 1) AS users_pct_of_prev FROM funnel
UNION ALL
SELECT 'R3 delivery (per order)', 10, CASE IFNULL(shipping_tier, '') WHEN 'flat_rate:1' THEN 'Flat rate delivery' WHEN 'pickup_location:0' THEN 'Pickup (Richmond store)' WHEN '' THEN 'No shipping (digital-only)' ELSE shipping_tier END, NULL, COUNT(*), NULL FROM ev WHERE event_name = 'add_shipping_info' GROUP BY 3
UNION ALL
SELECT 'R3 payment (per order)', 20, CASE payment_type WHEN 'bacs' THEN 'Direct bank transfer' WHEN 'cheque' THEN 'Check payments' WHEN 'cod' THEN 'Cash on delivery' ELSE IFNULL(payment_type, '(not set)') END, NULL, COUNT(*), NULL FROM ev WHERE event_name = 'add_payment_info' GROUP BY 3;
