WITH amplitude_events AS (
  SELECT
    ep_house_id AS id_house,
    id_amplitude,
    LOWER(business_context) AS business_context
  FROM
    datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE
    DATE(CAST(year AS STRING) || CAST(month AS STRING) || CAST(day AS STRING)) >= (CURRENT_DATE - INTERVAL '30' DAY)
    AND ts_event >= (CURRENT_DATE - INTERVAL '7' DAY)
),
houses AS (
  SELECT
    llf.sk_house AS id_house,
    LOWER(llf.origin_table) AS business_context,
    MIN(dd.date) AS dt_first_listing
  FROM
    dw_datamarts.lead_listing_flows AS llf
  INNER JOIN
    dw_public.dim_date AS dd
      ON llf.sk_first_listing_date = dd.sk_date
  WHERE
    llf.sk_first_listing_date > 0
  GROUP BY 1, 2
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
      ON CAST(e.id_house AS BIGINT) = h.id_house
      AND e.business_context = h.business_context
  INNER JOIN
    dw_rent.dim_house_listing AS dhl
      ON dhl.id_house = h.id_house
  INNER JOIN
    dw_rent.fact_house_listings AS fhl
        ON dhl.sk_house_listing = fhl.sk_house_listing
  INNER JOIN
    dw_public.dim_region AS dr
      ON fhl.sk_region = dr.sk_region
      AND dr.country_code != 'MX'
  GROUP BY 1, 2, 3, 4
),
lpv_data AS (
  SELECT DISTINCT
    NOW() AS ts_event,
    CAST(m.sk_region AS BIGINT) AS id_region,
    CAST(m.neighborhood AS STRING) AS neighborhood,
    CAST(UPPER(m.business_context) AS STRING) AS business_context,
    CAST(MEDIAN(m.views_quantity) OVER(PARTITION BY m.business_context, m.sk_region) AS BIGINT) AS lpv_p_50,
    CAST(a.mdape_city AS FLOAT) AS mdape_city
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
  REGEXP_REPLACE(neighborhood, '\\n', '') AS neighborhood,
  business_context,
  lpv_p_50,
  mdape_city
FROM
  lpv_data
WHERE
  id_region IS NOT NULL
