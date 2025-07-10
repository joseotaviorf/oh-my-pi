/*
Calculates Catalog Coverage

Assumptions:
  - Any Item in a recset is also considered as being on the catalog.
  Otherwise the metric could be higher than 1.
*/

WITH dates AS (
    SELECT DISTINCT
        dt_rec_received,
        business_context,
        display_type
    FROM
        datalake_recommendations.recommendation
),

catalog_id_item AS (
    SELECT
        dates.dt_rec_received,
        dates.business_context,
        dates.display_type,
        recommendation_catalog.id_item AS id_item
    FROM
        dates
    LEFT JOIN
        datalake_recommendations.recommendation_catalog recommendation_catalog
    ON
        DATE(recommendation_catalog.ts_status_started) <= dates.dt_rec_received
        AND (
            DATE(recommendation_catalog.ts_status_ended) >= dates.dt_rec_received
            OR recommendation_catalog.ts_status_ended IS Null
        )
        AND dates.business_context = recommendation_catalog.business_context

    UNION ALL

    SELECT
        dt_rec_received,
        business_context,
        display_type,
        id_item
    FROM
        datalake_recommendations.recommendation
),

catalog AS (
  SELECT
      dt_rec_received,
      business_context,
      display_type,
      COUNT(DISTINCT id_item) AS catalog_items_per_day
  FROM
      catalog_id_item
  GROUP BY
      dt_rec_received, business_context, display_type
),

recommended AS (
SELECT
    dt_rec_received,
    business_context,
    display_type,
    COUNT(DISTINCT CASE WHEN item_rank <= 3 THEN id_item END ) AS distinct_recommended_items_per_day_at_3,
    COUNT(DISTINCT CASE WHEN item_rank <= 5 THEN id_item END ) AS distinct_recommended_items_per_day_at_5,
    COUNT(DISTINCT CASE WHEN item_rank <= 10 THEN id_item END ) AS distinct_recommended_items_per_day_at_10,
    SUM(CASE WHEN item_rank <= 3 THEN 1 ELSE 0 END) recommended_items_per_day_at_3,
    SUM(CASE WHEN item_rank <= 5 THEN 1 ELSE 0 END) recommended_items_per_day_at_5,
    SUM(CASE WHEN item_rank <= 10 THEN 1 ELSE 0 END) recommended_items_per_day_at_10
FROM
    datalake_recommendations.recommendation
GROUP BY
    dt_rec_received, business_context, display_type
)

SELECT
    dates.business_context,
    dates.display_type,
    distinct_recommended_items_per_day_at_3/
    LEAST(catalog_items_per_day, recommended_items_per_day_at_3) AS coverage_at_3,
    distinct_recommended_items_per_day_at_5/
    LEAST(catalog_items_per_day, recommended_items_per_day_at_5) AS coverage_at_5,
    distinct_recommended_items_per_day_at_10/
    LEAST(catalog_items_per_day, recommended_items_per_day_at_10) AS coverage_at_10,
    dates.dt_rec_received
FROM
    dates
LEFT JOIN
    recommended
ON dates.dt_rec_received = recommended.dt_rec_received
    AND dates.business_context = recommended.business_context
    AND dates.display_type = recommended.display_type
LEFT JOIN
    catalog
    ON dates.dt_rec_received = catalog.dt_rec_received
        AND dates.business_context = catalog.business_context

