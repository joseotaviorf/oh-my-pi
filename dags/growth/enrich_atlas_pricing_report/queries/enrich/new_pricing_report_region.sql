WITH amplitude_events AS (
  SELECT
    ep_house_id AS id_house,
    id_amplitude,
    LOWER(business_context) AS business_context
  FROM
    datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE
    DATE(year::STRING || month::STRING || day::STRING) >= (CURRENT_DATE - INTERVAL '30' DAY)
    AND ts_event >= (CURRENT_DATE - INTERVAL '7' DAY)
),
houses AS (
  SELECT
    llf.sk_house AS id_house,
    llf.sk_region,
    LOWER(llf.origin_table) AS business_context,
    MIN(dd.date) AS dt_first_listing
  FROM
    dw_datamarts.lead_listing_flows AS llf
  INNER JOIN
    dw_public.dim_date AS dd
      ON llf.sk_first_listing_date = dd.sk_date
  WHERE
    llf.sk_first_listing_date > 0
  GROUP BY 1, 2, 3
),
house_views AS (
  SELECT
    e.id_house,
    e.business_context,
    dr.sk_region,
    dr.name AS neighborhood,
    COUNT(DISTINCT e.id_amplitude) AS views_quantity
  FROM
    amplitude_events AS e
  INNER JOIN
    houses AS h
      ON e.id_house::BIGINT = h.id_house
      AND e.business_context = h.business_context
  INNER JOIN
    dw_public.dim_region AS dr
      ON h.sk_region = dr.sk_region
      AND dr.country_code != 'MX'
  GROUP BY 1, 2, 3, 4
),
lpv_data AS (
  SELECT DISTINCT
    NOW() AS ts_event,
    m.sk_region::BIGINT AS id_region,
    m.neighborhood::STRING,
    UPPER(m.business_context)::STRING AS business_context,
    MEDIAN(m.views_quantity) OVER(PARTITION BY m.business_context, m.sk_region)::BIGINT AS lpv_p_50,
    a.mdape_city::FLOAT
  FROM
    datalake_atlas_pricing_report.region_metrics AS a
  LEFT JOIN
    house_views AS m
      ON m.sk_region = a.id_region
      AND LOWER(m.business_context) = LOWER(a.business_context)
)
SELECT
  DATE_FORMAT(ts_event, 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_event,
  MONOTONICALLY_INCREASING_ID() AS id,
  id_region,
  neighborhood,
  business_context,
  lpv_p_50,
  mdape_city
FROM
  lpv_data
WHERE
  id_region IS NOT NULL
