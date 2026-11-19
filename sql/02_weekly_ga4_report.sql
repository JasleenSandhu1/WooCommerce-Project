-- =====================================================================
-- Weekly GA4 ecommerce report: last 7 full days (Vancouver) vs the 7 days before
-- BigQuery Standard SQL · validated 2026-11-18 against cascade-analytics-514821.analytics_564395689
-- No DECLARE statements, so each query runs as a single read-only SELECT.
-- GTM Preview (debug_mode = 1) traffic is excluded from every KPI.
-- =====================================================================

-- ---------------------------------------------------------------------
-- R1. Headline KPIs + data-quality counts, this week vs previous week
-- ---------------------------------------------------------------------
WITH params AS (
  SELECT DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 1 DAY) AS this_end
),
p AS (
  SELECT this_end, DATE_SUB(this_end, INTERVAL 6 DAY) AS this_start, DATE_SUB(this_end, INTERVAL 13 DAY) AS prev_start
  FROM params
),
ev AS (
  SELECT
    PARSE_DATE('%Y%m%d', e.event_date)                                                   AS d,
    IF(PARSE_DATE('%Y%m%d', e.event_date) >= p.this_start, 'this_week', 'prev_week')     AS period,
    e.event_name, e.user_pseudo_id,
    CONCAT(e.user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(e.event_params)
                                         WHERE key = 'ga_session_id') AS STRING))        AS session_key,
    NULLIF(NULLIF(e.ecommerce.transaction_id, ''), '(not set)')                          AS transaction_id,
    e.ecommerce.purchase_revenue                                                         AS revenue,
    COALESCE((SELECT value.int_value FROM UNNEST(e.event_params)
              WHERE key = 'debug_mode'), 0) = 1                                          AS is_debug
  FROM `cascade-analytics-514821.analytics_564395689.events_*` e, p
  WHERE e._TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', p.prev_start) AND FORMAT_DATE('%Y%m%d', p.this_end)
),
clean AS (SELECT * FROM ev WHERE NOT is_debug),
purchases AS (   -- one row per order; hits > 1 = duplicate purchase events
  SELECT period, transaction_id, MAX(revenue) AS revenue, COUNT(*) AS hits
  FROM clean WHERE event_name = 'purchase' AND transaction_id IS NOT NULL
  GROUP BY 1, 2
),
periods AS (SELECT 'this_week' AS period UNION ALL SELECT 'prev_week'),
traffic AS (SELECT period, COUNT(DISTINCT session_key) AS sessions, COUNT(DISTINCT user_pseudo_id) AS users FROM clean GROUP BY 1),
sales   AS (SELECT period, COUNT(*) AS orders, ROUND(SUM(revenue), 2) AS revenue_cad, COUNTIF(hits > 1) AS duplicate_ids FROM purchases GROUP BY 1),
dq      AS (SELECT period, COUNTIF(event_name = 'purchase' AND transaction_id IS NULL) AS purchases_missing_id,
                   COUNTIF(is_debug) AS debug_events_excluded FROM ev GROUP BY 1)
SELECT
  pr.period,
  (SELECT FORMAT('%t to %t', IF(pr.period = 'this_week', this_start, prev_start),
                 IF(pr.period = 'this_week', this_end, DATE_SUB(this_start, INTERVAL 1 DAY))) FROM p) AS date_range,
  IFNULL(t.sessions, 0)                                   AS sessions,
  IFNULL(t.users, 0)                                      AS users,
  IFNULL(s.orders, 0)                                     AS orders,
  IFNULL(s.revenue_cad, 0)                                AS revenue_cad,
  ROUND(SAFE_DIVIDE(s.orders, t.sessions) * 100, 2)       AS conversion_rate_pct,
  ROUND(SAFE_DIVIDE(s.revenue_cad, s.orders), 2)          AS aov_cad,
  IFNULL(s.duplicate_ids, 0)                              AS duplicate_ids,
  IFNULL(dq.purchases_missing_id, 0)                      AS purchases_missing_id,
  IFNULL(dq.debug_events_excluded, 0)                     AS debug_events_excluded
FROM periods pr
LEFT JOIN traffic t USING (period)
LEFT JOIN sales   s USING (period)
LEFT JOIN dq        USING (period)
ORDER BY pr.period DESC;


-- ---------------------------------------------------------------------
-- R2. Checkout funnel (distinct users per step, this week) and
-- R3. Delivery and payment mix (per order: one add_shipping_info / add_payment_info per placed order)
-- ---------------------------------------------------------------------
WITH p AS (
  SELECT DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 1 DAY) AS this_end,
         DATE_SUB(CURRENT_DATE('America/Vancouver'), INTERVAL 7 DAY) AS this_start
),
ev AS (
  SELECT e.event_name, e.user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'shipping_tier') AS shipping_tier,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'payment_type')  AS payment_type
  FROM `cascade-analytics-514821.analytics_564395689.events_*` e, p
  WHERE e._TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', p.this_start) AND FORMAT_DATE('%Y%m%d', p.this_end)
    AND COALESCE((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'debug_mode'), 0) = 0
),
steps AS (
  SELECT * FROM UNNEST([STRUCT(1 AS step_order, 'view_item' AS step), (2, 'add_to_cart'), (3, 'begin_checkout'),
                        (4, 'add_shipping_info'), (5, 'add_payment_info'), (6, 'purchase')])
),
funnel AS (
  SELECT s.step_order, s.step, COUNT(DISTINCT ev.user_pseudo_id) AS users, COUNT(ev.event_name) AS events
  FROM steps s LEFT JOIN ev ON ev.event_name = s.step
  GROUP BY 1, 2
)
SELECT 'R2 funnel' AS section, step_order AS sort, step AS label, users, events,
       ROUND(SAFE_DIVIDE(users, LAG(users) OVER (ORDER BY step_order)) * 100, 1) AS users_pct_of_prev
FROM funnel
UNION ALL
SELECT 'R3 delivery (per order)', 10, IFNULL(NULLIF(shipping_tier, ''), '(none: digital-only)'), NULL, COUNT(*), NULL
FROM ev WHERE event_name = 'add_shipping_info' GROUP BY 3
UNION ALL
SELECT 'R3 payment (per order)', 20, IFNULL(payment_type, '(not set)'), NULL, COUNT(*), NULL
FROM ev WHERE event_name = 'add_payment_info' GROUP BY 3
ORDER BY sort, events DESC;

-- Value labels for the report: flat_rate:1 = Flat rate delivery · pickup_location:0 = Pickup (Richmond store)
-- bacs = Direct bank transfer · cheque = Check payments · cod = Cash on delivery
