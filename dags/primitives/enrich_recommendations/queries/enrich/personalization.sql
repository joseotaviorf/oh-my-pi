WITH
base AS (
    SELECT DISTINCT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type
    FROM
        datalake_recommendations.recommendation AS recommendation
),

distinct_recset_at_3 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        COUNT(DISTINCT id_recset) AS distinct_recset,
        COUNT(DISTINCT id_item) AS distinct_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=3
    GROUP BY DATE(ts_rec_received), business_context, display_type
),


distinct_recset_by_item_at_3 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        id_item,
        COUNT(id_recset) AS distinct_recset_by_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=3
    GROUP BY
        DATE(ts_rec_received), business_context, display_type, id_item
),

min_personalization_at_3 AS (
  SELECT
      dt,
      business_context,
      display_type,
      1  - (
          ((distinct_recset - (distinct_item / 3) + 1) * (distinct_recset - (distinct_item / 3)))
          /((distinct_recset -1) * distinct_recset)
      ) AS min_personalization
  FROM distinct_recset_at_3
),

non_normalized_personalization_at_3 AS (
    SELECT
        DATE(recommendation.ts_rec_received) AS dt,
        recommendation.business_context,
        recommendation.display_type,
        1 - (MEAN(distinct_recset_by_item-1) / MAX(distinct_recset-1)) AS non_normalized_personalization
    FROM
        datalake_recommendations.recommendation AS recommendation
    LEFT JOIN
        distinct_recset_by_item_at_3
        ON DATE(recommendation.ts_rec_received) = distinct_recset_by_item_at_3.dt
        AND recommendation.business_context = distinct_recset_by_item_at_3.business_context
        AND recommendation.display_type = distinct_recset_by_item_at_3.display_type
        AND recommendation.id_item = distinct_recset_by_item_at_3.id_item
    LEFT JOIN
        distinct_recset_at_3
        ON DATE(recommendation.ts_rec_received) = distinct_recset_at_3.dt
        AND recommendation.business_context = distinct_recset_at_3.business_context
        AND recommendation.display_type = distinct_recset_at_3.display_type
    WHERE
    recommendation.item_rank <= 3
    GROUP BY DATE(recommendation.ts_rec_received), recommendation.business_context, recommendation.display_type
),

distinct_recset_at_5 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        COUNT(DISTINCT id_recset) AS distinct_recset,
        COUNT(DISTINCT id_item) AS distinct_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=5
    GROUP BY DATE(ts_rec_received), business_context, display_type
),

distinct_recset_by_item_at_5 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        id_item,
        COUNT(id_recset) AS distinct_recset_by_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=5
    GROUP BY
        DATE(ts_rec_received), business_context, display_type, id_item
),

min_personalization_at_5 AS (
  SELECT
      dt,
      business_context,
      display_type,
      1  - (
          ((distinct_recset - (distinct_item / 5) + 1) * (distinct_recset - (distinct_item / 5)))
          /((distinct_recset -1) * distinct_recset)
      ) AS min_personalization
  FROM distinct_recset_at_5
),

non_normalized_personalization_at_5 AS (
    SELECT
        DATE(recommendation.ts_rec_received) AS dt,
        recommendation.business_context,
        recommendation.display_type,
        1 - (MEAN(distinct_recset_by_item-1) / MAX(distinct_recset-1)) AS non_normalized_personalization
    FROM
        datalake_recommendations.recommendation AS recommendation
    LEFT JOIN
        distinct_recset_by_item_at_5
        ON DATE(recommendation.ts_rec_received) = distinct_recset_by_item_at_5.dt
        AND recommendation.business_context = distinct_recset_by_item_at_5.business_context
        AND recommendation.display_type = distinct_recset_by_item_at_5.display_type
        AND recommendation.id_item = distinct_recset_by_item_at_5.id_item
    LEFT JOIN
        distinct_recset_at_5
        ON DATE(recommendation.ts_rec_received) = distinct_recset_at_5.dt
        AND recommendation.business_context = distinct_recset_at_5.business_context
        AND recommendation.display_type = distinct_recset_at_5.display_type
    WHERE
    recommendation.item_rank <= 5
    GROUP BY DATE(recommendation.ts_rec_received), recommendation.business_context, recommendation.display_type
),

distinct_recset_at_10 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        COUNT(DISTINCT id_recset) AS distinct_recset,
        COUNT(DISTINCT id_item) AS distinct_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=10
    GROUP BY DATE(ts_rec_received), business_context, display_type
),

distinct_recset_by_item_at_10 AS (
    SELECT
        DATE(ts_rec_received) AS dt,
        business_context,
        display_type,
        id_item,
        COUNT(id_recset) AS distinct_recset_by_item
    FROM
        datalake_recommendations.recommendation AS recommendation
    WHERE
        item_rank<=10
    GROUP BY
        DATE(ts_rec_received), business_context, display_type, id_item
),

min_personalization_at_10 AS (
  SELECT
      dt,
      business_context,
      display_type,
      1  - (
          ((distinct_recset - (distinct_item / 10) + 1) * (distinct_recset - (distinct_item / 10)))
          /((distinct_recset -1) * distinct_recset)
      ) AS min_personalization
  FROM distinct_recset_at_10
),

non_normalized_personalization_at_10 AS (
    SELECT
        DATE(recommendation.ts_rec_received) AS dt,
        recommendation.business_context,
        recommendation.display_type,
        1 - (MEAN(distinct_recset_by_item-1) / MAX(distinct_recset-1)) AS non_normalized_personalization
    FROM
        datalake_recommendations.recommendation AS recommendation
    LEFT JOIN
        distinct_recset_by_item_at_10
        ON DATE(recommendation.ts_rec_received) = distinct_recset_by_item_at_10.dt
        AND recommendation.business_context = distinct_recset_by_item_at_10.business_context
        AND recommendation.display_type = distinct_recset_by_item_at_10.display_type
        AND recommendation.id_item = distinct_recset_by_item_at_10.id_item
    LEFT JOIN
        distinct_recset_at_10
        ON DATE(recommendation.ts_rec_received) = distinct_recset_at_10.dt
        AND recommendation.business_context = distinct_recset_at_10.business_context
        AND recommendation.display_type = distinct_recset_at_10.display_type
    WHERE
    recommendation.item_rank <= 10
    GROUP BY DATE(recommendation.ts_rec_received), recommendation.business_context, recommendation.display_type
),

personalization_at_3 AS (
SELECT
    non_normalized_personalization_at_3.dt,
    non_normalized_personalization_at_3.business_context,
    non_normalized_personalization_at_3.display_type,
    COALESCE((non_normalized_personalization - min_personalization) / (1-min_personalization), 0) AS personalization_at_3
FROM
    non_normalized_personalization_at_3
LEFT JOIN min_personalization_at_3
    ON non_normalized_personalization_at_3.dt = min_personalization_at_3.dt
    AND non_normalized_personalization_at_3.business_context = min_personalization_at_3.business_context
    AND non_normalized_personalization_at_3.display_type = min_personalization_at_3.display_type
),

personalization_at_5 AS (
SELECT
    non_normalized_personalization_at_5.dt,
    non_normalized_personalization_at_5.business_context,
    non_normalized_personalization_at_5.display_type,
    COALESCE((non_normalized_personalization - min_personalization) / (1-min_personalization), 0) AS personalization_at_5
FROM
    non_normalized_personalization_at_5
LEFT JOIN min_personalization_at_5
    ON non_normalized_personalization_at_5.dt = min_personalization_at_5.dt
    AND non_normalized_personalization_at_5.business_context = min_personalization_at_5.business_context
    AND non_normalized_personalization_at_5.display_type = min_personalization_at_5.display_type
),

personalization_at_10 AS (
SELECT
    non_normalized_personalization_at_10.dt,
    non_normalized_personalization_at_10.business_context,
    non_normalized_personalization_at_10.display_type,
    COALESCE((non_normalized_personalization - min_personalization) / (1-min_personalization), 0) AS personalization_at_10
FROM
    non_normalized_personalization_at_10
LEFT JOIN min_personalization_at_10
    ON non_normalized_personalization_at_10.dt = min_personalization_at_10.dt
    AND non_normalized_personalization_at_10.business_context = min_personalization_at_10.business_context
    AND non_normalized_personalization_at_10.display_type = min_personalization_at_10.display_type
)

SELECT
    base.dt,
    base.business_context,
    base.display_type,
    personalization_at_3,
    personalization_at_5,
    personalization_at_10
FROM
    base
LEFT JOIN
    personalization_at_3
    ON base.dt = personalization_at_3.dt
    AND base.business_context = personalization_at_3.business_context
    AND base.display_type = personalization_at_3.display_type
LEFT JOIN
    personalization_at_5
    ON base.dt = personalization_at_5.dt
    AND base.business_context = personalization_at_5.business_context
    AND base.display_type = personalization_at_5.display_type
LEFT JOIN
    personalization_at_10
    ON base.dt = personalization_at_10.dt
    AND base.business_context = personalization_at_10.business_context
    AND base.display_type = personalization_at_10.display_type
