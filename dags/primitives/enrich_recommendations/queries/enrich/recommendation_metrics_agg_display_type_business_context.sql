/*
Recommendation metrics aggregated by dt_rec_received, business_context, display_type
Aggregation func: min, mean, max
*/

SELECT
    r.business_context,
    r.display_type,

    SUM(count_recsets) AS count_recsets,

    SUM(sum_precision_at_3) / SUM(count_recsets) AS mean_precision_at_3,
    SUM(sum_precision_at_5) / SUM(count_recsets) AS mean_precision_at_5,
    SUM(sum_precision_at_10) / SUM(count_recsets) AS mean_precision_at_10,

    SUM(sum_recall_at_3) / SUM(count_recsets) AS mean_recall_at_3,
    SUM(sum_recall_at_5) / SUM(count_recsets) AS mean_recall_at_5,
    SUM(sum_recall_at_10) / SUM(count_recsets) AS mean_recall_at_10,

    SUM(sum_f1_at_3) / SUM(count_recsets) AS mean_f1_at_3,
    SUM(sum_f1_at_5) / SUM(count_recsets) AS mean_f1_at_5,
    SUM(sum_f1_at_10) / SUM(count_recsets) AS mean_f1_at_10,

    SUM(sum_hit_rate_at_3) / SUM(count_recsets) AS mean_hit_rate_at_3,
    SUM(sum_hit_rate_at_5) / SUM(count_recsets) AS mean_hit_rate_at_5,
    SUM(sum_hit_rate_at_10) / SUM(count_recsets) AS mean_hit_rate_at_10,

    SUM(sum_rr_at_3) / SUM(count_recsets) AS mean_rr_at_3,
    SUM(sum_rr_at_5) / SUM(count_recsets) AS mean_rr_at_5,
    SUM(sum_rr_at_10) / SUM(count_recsets) AS mean_rr_at_10,

    SUM(sum_ap_at_3) / SUM(count_recsets) AS mean_ap_at_3,
    SUM(sum_ap_at_5) / SUM(count_recsets) AS mean_ap_at_5,
    SUM(sum_ap_at_10) / SUM(count_recsets) AS mean_ap_at_10,

    SUM(sum_ndcg_at_3) / SUM(count_recsets) AS mean_ndcg_at_3,
    SUM(sum_ndcg_at_5) / SUM(count_recsets) AS mean_ndcg_at_5,
    SUM(sum_ndcg_at_10) / SUM(count_recsets) AS mean_ndcg_at_10,

    -- SUM(sum_diversity_at_3) / SUM(count_recsets) AS mean_diversity_at_3,
    -- SUM(sum_diversity_at_5) / SUM(count_recsets) AS mean_diversity_at_5,
    -- SUM(sum_diversity_at_10) / SUM(count_recsets) AS mean_diversity_at_10,

    SUM(sum_repetition_at_3) / SUM(count_recsets) AS mean_repetition_at_3,
    SUM(sum_repetition_at_5) / SUM(count_recsets) AS mean_repetition_at_5,
    SUM(sum_repetition_at_10) / SUM(count_recsets) AS mean_repetition_at_10,

    SUM(sum_rec_to_favorite_at_3) / SUM(count_recsets) AS mean_rec_to_favorite_at_3,
    SUM(sum_rec_to_favorite_at_5) / SUM(count_recsets) AS mean_rec_to_favorite_at_5,
    SUM(sum_rec_to_favorite_at_10) / SUM(count_recsets) AS mean_rec_to_favorite_at_10,

    SUM(sum_rec_to_sale_flow_one_day_at_3) / SUM(count_recsets) AS mean_rec_to_sale_flow_one_day_at_3,
    SUM(sum_rec_to_sale_flow_one_day_at_5) / SUM(count_recsets) AS mean_rec_to_sale_flow_one_day_at_5,
    SUM(sum_rec_to_sale_flow_one_day_at_10) / SUM(count_recsets) AS mean_rec_to_sale_flow_one_day_at_10,

    SUM(sum_rec_to_sale_flow_fourteen_days_at_3) / SUM(count_recsets) AS mean_rec_to_sale_flow_fourteen_days_at_3,
    SUM(sum_rec_to_sale_flow_fourteen_days_at_5) / SUM(count_recsets) AS mean_rec_to_sale_flow_fourteen_days_at_5,
    SUM(sum_rec_to_sale_flow_fourteen_days_at_10) / SUM(count_recsets) AS mean_rec_to_sale_flow_fourteen_days_at_10,

    SUM(sum_rec_to_rent_flow_one_day_at_3) / SUM(count_recsets) AS mean_rec_to_rent_flow_one_day_at_3,
    SUM(sum_rec_to_rent_flow_one_day_at_5) / SUM(count_recsets) AS mean_rec_to_rent_flow_one_day_at_5,
    SUM(sum_rec_to_rent_flow_one_day_at_10) / SUM(count_recsets) AS mean_rec_to_rent_flow_one_day_at_10,

    SUM(sum_rec_to_rent_flow_seven_days_at_3) / SUM(count_recsets) AS mean_rec_to_rent_flow_seven_days_at_3,
    SUM(sum_rec_to_rent_flow_seven_days_at_5) / SUM(count_recsets) AS mean_rec_to_rent_flow_seven_days_at_5,
    SUM(sum_rec_to_rent_flow_seven_days_at_10) / SUM(count_recsets) AS mean_rec_to_rent_flow_seven_days_at_10,

    SUM(sum_hit_rec_to_sale_flow_one_day_at_3) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_one_day_at_3,
    SUM(sum_hit_rec_to_sale_flow_one_day_at_5) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_one_day_at_5,
    SUM(sum_hit_rec_to_sale_flow_one_day_at_10) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_one_day_at_10,

    SUM(sum_hit_rec_to_sale_flow_fourteen_days_at_3) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_fourteen_days_at_3,
    SUM(sum_hit_rec_to_sale_flow_fourteen_days_at_5) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_fourteen_days_at_5,
    SUM(sum_hit_rec_to_sale_flow_fourteen_days_at_10) / SUM(count_recsets) AS mean_hit_rec_to_sale_flow_fourteen_days_at_10,

    SUM(sum_hit_rec_to_rent_flow_one_day_at_3) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_one_day_at_3,
    SUM(sum_hit_rec_to_rent_flow_one_day_at_5) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_one_day_at_5,
    SUM(sum_hit_rec_to_rent_flow_one_day_at_10) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_one_day_at_10,

    SUM(sum_hit_rec_to_rent_flow_seven_days_at_3) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_seven_days_at_3,
    SUM(sum_hit_rec_to_rent_flow_seven_days_at_5) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_seven_days_at_5,
    SUM(sum_hit_rec_to_rent_flow_seven_days_at_10) / SUM(count_recsets) AS mean_hit_rec_to_rent_flow_seven_days_at_10,

    SUM(sum_popularity_at_3) / SUM(count_recsets) AS mean_popularity_at_3,
    SUM(sum_popularity_at_5) / SUM(count_recsets) AS mean_popularity_at_5,
    SUM(sum_popularity_at_10) / SUM(count_recsets) AS mean_popularity_at_10,

    MEAN(coverage_at_3) AS mean_coverage_at_3,
    MEAN(coverage_at_5) AS mean_coverage_at_5,
    MEAN(coverage_at_10) AS mean_coverage_at_10,

    r.dt_rec_received

FROM
    datalake_recommendations.recommendation_metrics_agg_dimensions r
LEFT JOIN
    datalake_recommendations.coverage AS c
    ON r.dt_rec_received = c.dt_rec_received
        AND r.business_context = c.business_context
        AND r.display_type = c.display_type
WHERE
    r.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
GROUP BY
    r.dt_rec_received,
    r.business_context,
    r.display_type
