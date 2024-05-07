WITH listing_base AS (
  SELECT
    lst.id_house,
    lst.business_context,
    lst.status,
    lst.price,
    LEAD(lst.status) OVER(PARTITION BY lst.id_house, lst.business_context ORDER BY lst.ts_status_started) AS next_status,
    lst.ts_status_started
  FROM
    datalake_atlas_pricing_report.status_history_house_listing AS lst
  UNION ALL
  SELECT
    chg.id_house,
    chg.business_context,
    chg.status,
    chg.price,
    NULL AS next_status,
    chg.ts_price_started AS ts_status_started
  FROM
    datalake_atlas_pricing_report.status_history_house_price_change AS chg
  UNION ALL
  SELECT
    neg.id_house,
    neg.business_context,
    neg.status,
    neg.price,
    NULL AS next_status,
    neg.ts_status_started
  FROM
    datalake_atlas_pricing_report.status_history_house_negotiation AS neg
),
negotiation_windows AS (
  SELECT
    lb.id_house,
    lb.business_context,
    lb.status,
    lb.price,
    lb.next_status,
    lb.ts_status_started,
    MIN(neg.ts_status_started) AS next_negotiation
  FROM
    listing_base AS lb
  LEFT JOIN
    datalake_atlas_pricing_report.status_history_house_negotiation AS neg
      ON neg.id_house = lb.id_house
        AND neg.business_context = lb.business_context
        AND neg.ts_status_started >= lb.ts_status_started
  GROUP BY ALL
),
history_status AS (
  SELECT
    nw.id_house,
    nw.business_context,
    nw.status,
    nw.next_status,
    nw.price,
    nw.next_negotiation,
    nw.ts_status_started,
    ROW_NUMBER()
      OVER(
        PARTITION BY nw.id_house, nw.status, nw.next_negotiation, nw.business_context
        ORDER BY nw.ts_status_started
      ) AS first_status,
    ROW_NUMBER()
      OVER(
        PARTITION BY nw.id_house, nw.status, nw.next_negotiation, nw.business_context
        ORDER BY nw.ts_status_started DESC
      ) AS last_status,
    ROW_NUMBER()
      OVER(
        PARTITION BY nw.id_house, nw.next_negotiation, nw.business_context
        ORDER BY nw.ts_status_started
      ) AS window_order
  FROM
    negotiation_windows AS nw
),
avoiding_redundancy AS (
  SELECT
    id_house,
    business_context,
    status,
    price,
    LAG(price) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS previous_price,
    LAG(status) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS previous_status,
    LEAD(price) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS next_price,
    LEAD(status) OVER(PARTITION BY id_house, business_context ORDER BY ts_status_started) AS next_status,
    ts_status_started
  FROM
    history_status
  WHERE
    (
      (status = 'PUBLISHED' AND first_status = 1)
      OR (status = 'PRICE_CHANGE' AND last_status = 1 AND window_order > 1)
      OR (status = 'UNPUBLISHED' AND next_negotiation IS NULL AND last_status = 1 AND COALESCE(next_status,'N/A') <> 'PUBLISHED')
      OR (status = 'NEGOTIATED' AND window_order > 1)
    )
)
SELECT
  DATE_FORMAT(NOW(), 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_event,
  MONOTONICALLY_INCREASING_ID() AS id,
  id_house::BIGINT,
  business_context::STRING,
  ROUND(price::FLOAT, 2) AS price,
  status::STRING,
  DATE_FORMAT(ts_status_started, 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_status_started
FROM
  avoiding_redundancy
WHERE
  1 = CASE
        WHEN status = 'PRICE_CHANGE' AND previous_price = price AND previous_status = 'PUBLISHED' THEN 0
        WHEN status = 'PRICE_CHANGE' AND next_price = price AND next_status = 'PUBLISHED' THEN 0
        ELSE 1
      END
