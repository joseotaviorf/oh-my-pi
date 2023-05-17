/*
Recommendation metrics aggregated by dt_rec_received, business_context, display_type, experiment, experiment_variant
Aggregation func: min, mean, max
*/

SELECT
    r.business_context,
    r.display_type,
    r.experiment,
    r.experiment_variant,

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

    SUM(sum_diversity_at_3) / SUM(count_recsets) AS mean_diversity_at_3,
    SUM(sum_diversity_at_5) / SUM(count_recsets) AS mean_diversity_at_5,
    SUM(sum_diversity_at_10) / SUM(count_recsets) AS mean_diversity_at_10,

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

    r.dt_rec_received
FROM
    datalake_recommendations.recommendation_metrics_agg_dimensions r
GROUP BY
    r.dt_rec_received,
    r.business_context,
    r.display_type,
    r.experiment,
    r.experiment_variant
