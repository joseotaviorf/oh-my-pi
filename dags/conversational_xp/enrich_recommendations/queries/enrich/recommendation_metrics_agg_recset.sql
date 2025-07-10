/*
Recommendation metrics aggregated by Recset
*/


/*
Calculate the ideal discounted cumulative gain
*/
WITH idcg AS (
    WITH _k AS (
        SELECT * FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10)) AS DE(k)
    )

    SELECT
        k1.k,
        SUM(1/log2(k2.k+1)) AS idcg_k
    FROM _k AS k1
    LEFT JOIN
        _k AS k2
            ON k2.k <= k1.k
    GROUP BY 1
),

recommendation_feats AS
(
SELECT recommendation_flow.*,
    -- COALESCE(diversity.diversity_at_3, 0) AS diversity_at_3,
    -- COALESCE(diversity.diversity_at_5, 0) AS diversity_at_5,
    -- COALESCE(diversity.diversity_at_10, 0) AS diversity_at_10,
    COALESCE(popularity.popularity, 0) AS popularity,
    idcg_k
FROM datalake_recommendations.recommendation_flow AS recommendation_flow
-- LEFT JOIN
    -- datalake_recommendations.diversity AS diversity
        -- ON recommendation_flow.id_recset = diversity.id_recset
LEFT JOIN
    datalake_recommendations.popularity AS popularity
    ON recommendation_flow.id_rec = popularity.id_rec
LEFT JOIN
    idcg
        ON idcg.k = recommendation_flow.item_rank
WHERE
    recommendation_flow.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

base AS (
    SELECT DISTINCT
        id_recset,
        business_context,
        type_subject,
        type_item,
        display_type,
        ml_model,
        country,
        region,
        city,
        device_family,
        platform,
        language,
        experiments,
        experiments_variants,
        ts_rec_created,
        DATE(ts_rec_created) AS dt_rec_created,
        dt_rec_received,
        year,
        month,
        day
    FROM
        datalake_recommendations.recommendation_flow AS recommendation_flow
    WHERE
        recommendation_flow.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

metrics_at_3 AS (
    SELECT
        id_recset,
        SUM(INT(true_positive)) / COUNT(item_rank) AS precision_at_3,
        COALESCE(SUM(INT(true_positive)) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS recall_at_3,
        MAX(INT(true_positive)) AS hit_rate_at_3,
        MAX(INT(true_positive) / item_rank) AS rr_at_3,
        COALESCE(SUM((INT(true_positive) * cum_true_positive) / item_rank) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS ap_at_3,
        SUM(INT(true_positive) / log2(item_rank+1)) / MAX(idcg_k) AS ndcg_at_3,
        -- MEAN(diversity_at_3) AS diversity_at_3,
        SUM(INT(repeated_rec)) / COUNT(item_rank) AS repetition_at_3,
        SUM(INT(rec_to_favorite)) / COUNT(item_rank) AS rec_to_favorite_at_3,
        MAX(INT(rec_to_sale_flow_one_day)) AS hit_rec_to_sale_flow_one_day_at_3,
        MAX(INT(rec_to_sale_flow_fourteen_days)) AS hit_rec_to_sale_flow_fourteen_days_at_3,
        MAX(INT(rec_to_rent_flow_one_day)) AS hit_rec_to_rent_flow_one_day_at_3,
        MAX(INT(rec_to_rent_flow_seven_days)) AS hit_rec_to_rent_flow_seven_days_at_3,
        SUM(INT(rec_to_sale_flow_one_day)) / COUNT(item_rank) AS rec_to_sale_flow_one_day_at_3,
        SUM(INT(rec_to_sale_flow_fourteen_days)) / COUNT(item_rank) AS rec_to_sale_flow_fourteen_days_at_3,
        SUM(INT(rec_to_rent_flow_one_day)) / COUNT(item_rank) AS rec_to_rent_flow_one_day_at_3,
        SUM(INT(rec_to_rent_flow_seven_days)) / COUNT(item_rank) AS rec_to_rent_flow_seven_days_at_3,
        MEAN(popularity) AS popularity_at_3,
        SUM(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS true_positive_and_sale_flow_fourteen_days_at_3,
        SUM(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS true_positive_and_rent_flow_seven_days_at_3,
        MAX(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS hit_true_positive_and_sale_flow_fourteen_days_at_3,
        MAX(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS hit_true_positive_and_rent_flow_seven_days_at_3,
        SUM(INT(true_positive)) AS count_true_positive_at_3
    FROM
        recommendation_feats
    WHERE
        item_rank <= 3
    GROUP BY 1
),

metrics_at_5 AS (
    SELECT
        id_recset,
        SUM(INT(true_positive)) / COUNT(item_rank) AS precision_at_5,
        COALESCE(SUM(INT(true_positive)) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS recall_at_5,
        MAX(INT(true_positive)) AS hit_rate_at_5,
        MAX(INT(true_positive) / item_rank) AS rr_at_5,
        COALESCE(SUM((INT(true_positive) * cum_true_positive) / item_rank) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS ap_at_5,
        SUM(INT(true_positive) / log2(item_rank+1)) / MAX(idcg_k) AS ndcg_at_5,
        -- MEAN(diversity_at_5) AS diversity_at_5,
        SUM(INT(repeated_rec)) / COUNT(item_rank) AS repetition_at_5,
        SUM(INT(rec_to_favorite)) / COUNT(item_rank) AS rec_to_favorite_at_5,
        MAX(INT(rec_to_sale_flow_one_day)) AS hit_rec_to_sale_flow_one_day_at_5,
        MAX(INT(rec_to_sale_flow_fourteen_days)) AS hit_rec_to_sale_flow_fourteen_days_at_5,
        MAX(INT(rec_to_rent_flow_one_day)) AS hit_rec_to_rent_flow_one_day_at_5,
        MAX(INT(rec_to_rent_flow_seven_days)) AS hit_rec_to_rent_flow_seven_days_at_5,
        SUM(INT(rec_to_sale_flow_one_day)) / COUNT(item_rank) AS rec_to_sale_flow_one_day_at_5,
        SUM(INT(rec_to_sale_flow_fourteen_days)) / COUNT(item_rank) AS rec_to_sale_flow_fourteen_days_at_5,
        SUM(INT(rec_to_rent_flow_one_day)) / COUNT(item_rank) AS rec_to_rent_flow_one_day_at_5,
        SUM(INT(rec_to_rent_flow_seven_days)) / COUNT(item_rank) AS rec_to_rent_flow_seven_days_at_5,
        MEAN(popularity) AS popularity_at_5,
        SUM(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS true_positive_and_sale_flow_fourteen_days_at_5,
        SUM(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS true_positive_and_rent_flow_seven_days_at_5,
        MAX(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS hit_true_positive_and_sale_flow_fourteen_days_at_5,
        MAX(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS hit_true_positive_and_rent_flow_seven_days_at_5,
        SUM(INT(true_positive)) AS count_true_positive_at_5
   FROM
        recommendation_feats
    WHERE
        item_rank <= 5
    GROUP BY 1
),

metrics_at_10 AS
(
    SELECT
        id_recset,
        SUM(INT(true_positive)) / COUNT(item_rank) AS precision_at_10,
        COALESCE(SUM(INT(true_positive)) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS recall_at_10,
        MAX(INT(true_positive)) AS hit_rate_at_10,
        MAX(INT(true_positive) / item_rank) AS rr_at_10,
        COALESCE(SUM((INT(true_positive) * cum_true_positive) / item_rank) / LEAST(MAX(count_relevant_items), COUNT(item_rank)), 0) AS ap_at_10,
        SUM(INT(true_positive) / log2(item_rank+1)) / MAX(idcg_k) AS ndcg_at_10,
        -- MEAN(diversity_at_10) AS diversity_at_10,
        SUM(INT(repeated_rec)) / COUNT(item_rank) AS repetition_at_10,
        SUM(INT(rec_to_favorite)) / COUNT(item_rank) AS rec_to_favorite_at_10,
        MAX(INT(rec_to_sale_flow_one_day)) AS hit_rec_to_sale_flow_one_day_at_10,
        MAX(INT(rec_to_sale_flow_fourteen_days)) AS hit_rec_to_sale_flow_fourteen_days_at_10,
        MAX(INT(rec_to_rent_flow_one_day)) AS hit_rec_to_rent_flow_one_day_at_10,
        MAX(INT(rec_to_rent_flow_seven_days)) AS hit_rec_to_rent_flow_seven_days_at_10,
        SUM(INT(rec_to_sale_flow_one_day)) / COUNT(item_rank) AS rec_to_sale_flow_one_day_at_10,
        SUM(INT(rec_to_sale_flow_fourteen_days)) / COUNT(item_rank) AS rec_to_sale_flow_fourteen_days_at_10,
        SUM(INT(rec_to_rent_flow_one_day)) / COUNT(item_rank) AS rec_to_rent_flow_one_day_at_10,
        SUM(INT(rec_to_rent_flow_seven_days)) / COUNT(item_rank) AS rec_to_rent_flow_seven_days_at_10,
        MEAN(popularity) AS popularity_at_10,
        SUM(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS true_positive_and_sale_flow_fourteen_days_at_10,
        SUM(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS true_positive_and_rent_flow_seven_days_at_10,
        MAX(INT(rec_to_sale_flow_fourteen_days) * INT(true_positive)) AS hit_true_positive_and_sale_flow_fourteen_days_at_10,
        MAX(INT(rec_to_rent_flow_seven_days) * INT(true_positive)) AS hit_true_positive_and_rent_flow_seven_days_at_10,
        SUM(INT(true_positive)) AS count_true_positive_at_10
    FROM
        recommendation_feats
    WHERE
        item_rank <= 10
    GROUP BY 1
)

SELECT base.*,

--k_3
precision_at_3,
recall_at_3,
COALESCE(2 * (precision_at_3 * recall_at_3) / (precision_at_3 +recall_at_3), 0) as f1_at_3,
hit_rate_at_3,
rr_at_3,
ap_at_3,
ndcg_at_3,
-- diversity_at_3,
repetition_at_3,
rec_to_favorite_at_3,
rec_to_sale_flow_one_day_at_3,
rec_to_sale_flow_fourteen_days_at_3,
rec_to_rent_flow_one_day_at_3,
rec_to_rent_flow_seven_days_at_3,
hit_rec_to_sale_flow_one_day_at_3,
hit_rec_to_sale_flow_fourteen_days_at_3,
hit_rec_to_rent_flow_one_day_at_3,
hit_rec_to_rent_flow_seven_days_at_3,
popularity_at_3,
true_positive_and_sale_flow_fourteen_days_at_3,
true_positive_and_rent_flow_seven_days_at_3,
hit_true_positive_and_sale_flow_fourteen_days_at_3,
hit_true_positive_and_rent_flow_seven_days_at_3,
count_true_positive_at_3,

--k_5
precision_at_5,
recall_at_5,
COALESCE(2 * (precision_at_5 * recall_at_5) / (precision_at_5 +recall_at_5), 0) as f1_at_5,
hit_rate_at_5,
rr_at_5,
ap_at_5,
ndcg_at_5,
-- diversity_at_5,
repetition_at_5,
rec_to_favorite_at_5,
rec_to_sale_flow_one_day_at_5,
rec_to_sale_flow_fourteen_days_at_5,
rec_to_rent_flow_one_day_at_5,
rec_to_rent_flow_seven_days_at_5,
hit_rec_to_sale_flow_one_day_at_5,
hit_rec_to_sale_flow_fourteen_days_at_5,
hit_rec_to_rent_flow_one_day_at_5,
hit_rec_to_rent_flow_seven_days_at_5,
popularity_at_5,
true_positive_and_sale_flow_fourteen_days_at_5,
true_positive_and_rent_flow_seven_days_at_5,
hit_true_positive_and_sale_flow_fourteen_days_at_5,
hit_true_positive_and_rent_flow_seven_days_at_5,
count_true_positive_at_5,

--k_10
precision_at_10,
recall_at_10,
COALESCE(2 * (precision_at_10 * recall_at_10) / (precision_at_10 +recall_at_10), 0) as f1_at_10,
hit_rate_at_10,
rr_at_10,
ap_at_10,
ndcg_at_10,
-- diversity_at_10,
repetition_at_10,
rec_to_favorite_at_10,
rec_to_sale_flow_one_day_at_10,
rec_to_sale_flow_fourteen_days_at_10,
rec_to_rent_flow_one_day_at_10,
rec_to_rent_flow_seven_days_at_10,
hit_rec_to_sale_flow_one_day_at_10,
hit_rec_to_sale_flow_fourteen_days_at_10,
hit_rec_to_rent_flow_one_day_at_10,
hit_rec_to_rent_flow_seven_days_at_10,
popularity_at_10,
true_positive_and_sale_flow_fourteen_days_at_10,
true_positive_and_rent_flow_seven_days_at_10,
hit_true_positive_and_sale_flow_fourteen_days_at_10,
hit_true_positive_and_rent_flow_seven_days_at_10,
count_true_positive_at_10

FROM
    base
LEFT JOIN
    metrics_at_3
        ON base.id_recset = metrics_at_3.id_recset
LEFT JOIN
    metrics_at_5
        ON base.id_recset = metrics_at_5.id_recset
LEFT JOIN
    metrics_at_10
        ON base.id_recset = metrics_at_10.id_recset
