WITH lpvs_consolidated AS (
  SELECT
    ol.sk_house,
    SUM(ol.qt_listing_page_viewed) AS total_lpv,
    SUM(ol.qt_visits_booked) AS total_vb,
    SUM(ol.qt_offers_submitted) AS total_os
  FROM
    dw_sale.fact_daily_ongoing_listing AS ol
  WHERE
    MAKE_DATE(ol.year, ol.month, ol.day) >= DATE('{load_end_date}') - INTERVAL 60 DAY
  GROUP BY ALL
),
demand_score AS (
  SELECT
    lpv.sk_house,
    CASE
      WHEN lpv.total_os > 0 THEN 5
      WHEN lpv.total_vb > 1 THEN 4
      WHEN lpv.total_lpv >= 100 OR lpv.total_vb > 0 THEN 3
      WHEN lpv.total_lpv >= 20 THEN 2
      WHEN lpv.total_lpv < 20 THEN 1
    END AS general_demand_score
  FROM
    lpvs_consolidated AS lpv
)
SELECT
  UUID() AS id,
  CAST(CONCAT(dl.sk_house, DATE_FORMAT(DATE('{load_end_date}'), 'yyyyMMdd')) AS STRING) AS business_id,
  dl.sk_house AS id_house,
  COALESCE(dc.uuid_company, '1P') AS company_uuid,
  'SALE' AS business_context,
  CASE
    WHEN fl.days_as_published <= 30 AND ds.general_demand_score < 3 THEN 3
    WHEN fl.days_as_published <= 60 AND ds.general_demand_score < 2 THEN 2
    ELSE ds.general_demand_score
  END AS demand_score,
  YEAR('{load_end_date}') AS year,
  MONTH('{load_end_date}') AS month,
  DAY('{load_end_date}') AS day
FROM
  dw_sale.dim_listing AS dl
INNER JOIN
  dw_sale.fact_listings AS fl
    ON dl.sk_house = fl.sk_house
LEFT JOIN
  demand_score AS ds
    ON dl.sk_house = ds.sk_house
LEFT JOIN
  dw_rede.dim_company AS dc
    ON fl.sk_company = dc.sk_company
WHERE
  dl.status = 'PUBLISHED'
LIMIT 10