WITH amplitude_events AS (
  SELECT
    lpve.ep_house_id AS id_house,
    UPPER(lpve.business_context) AS business_context,
    COUNT(DISTINCT lpve.id_amplitude) AS views_quantity
  FROM
    datalake_amplitude_clean.170698_listing_page_viewed_events AS lpve
  WHERE
    DATE(CAST(lpve.year AS STRING) || CAST(lpve.month AS STRING) || CAST(lpve.day AS STRING)) >= (CURRENT_DATE - INTERVAL '30' DAY)
    AND lpve.ts_event >= (CURRENT_DATE - INTERVAL '7' DAY)
  GROUP BY
    lpve.ep_house_id,
    UPPER(lpve.business_context)
),
similar_views AS (
  SELECT
    sl.id_house,
    sl.business_context,
    ae.views_quantity,
    PERCENTILE(e_similar.views_quantity, .25) AS similar_views_p25,
    PERCENTILE(e_similar.views_quantity, .75) AS similar_views_p75
  FROM
    datalake_atlas_pricing_report.similar_listings AS sl
  INNER JOIN
    amplitude_events AS ae
      ON sl.id_house = ae.id_house
      AND sl.business_context = ae.business_context
  INNER JOIN
    amplitude_events AS e_similar
      ON sl.similar_id_house = e_similar.id_house
      AND sl.business_context = e_similar.business_context
  GROUP BY
    sl.id_house,
    sl.business_context,
    ae.views_quantity
)
SELECT
  id_house,
  business_context,
  CASE
    WHEN views_quantity < similar_views_p25 THEN 'LOW'
    WHEN views_quantity > similar_views_p75 THEN 'HIGH'
    WHEN views_quantity >= similar_views_p25 AND views_quantity <= similar_views_p75 THEN 'MEDIUM'
  END AS demand_level,
  views_quantity
FROM
  similar_views
