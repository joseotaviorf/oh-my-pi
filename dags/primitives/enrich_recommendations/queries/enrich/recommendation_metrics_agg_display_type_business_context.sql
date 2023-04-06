/*
Recommendation metrics aggregated by dt_rec_received, business_context, display_type
Aggregation func: min, mean, max
*/

SELECT
    business_context,
    display_type,

    MEAN(precision_at_3) AS mean_precision_at_3,
    MIN(precision_at_3) AS min_precision_at_3,
    MAX(precision_at_3) AS max_precision_at_3,

    MEAN(precision_at_5) AS mean_precision_at_5,
    MIN(precision_at_5) AS min_precision_at_5,
    MAX(precision_at_5) AS max_precision_at_5,

    MEAN(precision_at_10) AS mean_precision_at_10,
    MIN(precision_at_10) AS min_precision_at_10,
    MAX(precision_at_10) AS max_precision_at_10,

    MEAN(recall_at_3) AS mean_recall_at_3,
    MIN(recall_at_3) AS min_recall_at_3,
    MAX(recall_at_3) AS max_recall_at_3,

    MEAN(recall_at_5) AS mean_recall_at_5,
    MIN(recall_at_5) AS min_recall_at_5,
    MAX(recall_at_5) AS max_recall_at_5,

    MEAN(recall_at_10) AS mean_recall_at_10,
    MIN(recall_at_10) AS min_recall_at_10,
    MAX(recall_at_10) AS max_recall_at_10,

    MEAN(f1_at_3) AS mean_f1_at_3,
    MIN(f1_at_3) AS min_f1_at_3,
    MAX(f1_at_3) AS max_f1_at_3,

    MEAN(f1_at_5) AS mean_f1_at_5,
    MIN(f1_at_5) AS min_f1_at_5,
    MAX(f1_at_5) AS max_f1_at_5,

    MEAN(f1_at_10) AS mean_f1_at_10,
    MIN(f1_at_10) AS min_f1_at_10,
    MAX(f1_at_10) AS max_f1_at_10,

    MEAN(hit_rate_at_3) AS mean_hit_rate_at_3,
    MIN(hit_rate_at_3) AS min_hit_rate_at_3,
    MAX(hit_rate_at_3) AS max_hit_rate_at_3,

    MEAN(hit_rate_at_5) AS mean_hit_rate_at_5,
    MIN(hit_rate_at_5) AS min_hit_rate_at_5,
    MAX(hit_rate_at_5) AS max_hit_rate_at_5,

    MEAN(hit_rate_at_10) AS mean_hit_rate_at_10,
    MIN(hit_rate_at_10) AS min_hit_rate_at_10,
    MAX(hit_rate_at_10) AS max_hit_rate_at_10,

    MEAN(rr_at_3) AS mean_rr_at_3,
    MIN(rr_at_3) AS min_rr_at_3,
    MAX(rr_at_3) AS max_rr_at_3,

    MEAN(rr_at_5) AS mean_rr_at_5,
    MIN(rr_at_5) AS min_rr_at_5,
    MAX(rr_at_5) AS max_rr_at_5,

    MEAN(rr_at_10) AS mean_rr_at_10,
    MIN(rr_at_10) AS min_rr_at_10,
    MAX(rr_at_10) AS max_rr_at_10,

    MEAN(ap_at_3) AS mean_ap_at_3,
    MIN(ap_at_3) AS min_ap_at_3,
    MAX(ap_at_3) AS max_ap_at_3,

    MEAN(ap_at_5) AS mean_ap_at_5,
    MIN(ap_at_5) AS min_ap_at_5,
    MAX(ap_at_5) AS max_ap_at_5,

    MEAN(ap_at_10) AS mean_ap_at_10,
    MIN(ap_at_10) AS min_ap_at_10,
    MAX(ap_at_10) AS max_ap_at_10,

    MEAN(ndcg_at_3) AS mean_ndcg_at_3,
    MIN(ndcg_at_3) AS min_ndcg_at_3,
    MAX(ndcg_at_3) AS max_ndcg_at_3,

    MEAN(ndcg_at_5) AS mean_ndcg_at_5,
    MIN(ndcg_at_5) AS min_ndcg_at_5,
    MAX(ndcg_at_5) AS max_ndcg_at_5,

    MEAN(ndcg_at_10) AS mean_ndcg_at_10,
    MIN(ndcg_at_10) AS min_ndcg_at_10,
    MAX(ndcg_at_10) AS max_ndcg_at_10,

    MEAN(rec_to_favorite_at_3) AS mean_rec_to_favorite_at_3,
    MIN(rec_to_favorite_at_3) AS min_rec_to_favorite_at_3,
    MAX(rec_to_favorite_at_3) AS max_rec_to_favorite_at_3,

    MEAN(rec_to_favorite_at_5) AS mean_rec_to_favorite_at_5,
    MIN(rec_to_favorite_at_5) AS min_rec_to_favorite_at_5,
    MAX(rec_to_favorite_at_5) AS max_rec_to_favorite_at_5,

    MEAN(rec_to_favorite_at_10) AS mean_rec_to_favorite_at_10,
    MIN(rec_to_favorite_at_10) AS min_rec_to_favorite_at_10,
    MAX(rec_to_favorite_at_10) AS max_rec_to_favorite_at_10,

    MEAN(rec_to_sale_flow_one_day_at_3) AS mean_rec_to_sale_flow_one_day_at_3,
    MIN(rec_to_sale_flow_one_day_at_3) AS min_rec_to_sale_flow_one_day_at_3,
    MAX(rec_to_sale_flow_one_day_at_3) AS max_rec_to_sale_flow_one_day_at_3,

    MEAN(rec_to_sale_flow_one_day_at_5) AS mean_rec_to_sale_flow_one_day_at_5,
    MIN(rec_to_sale_flow_one_day_at_5) AS min_rec_to_sale_flow_one_day_at_5,
    MAX(rec_to_sale_flow_one_day_at_5) AS max_rec_to_sale_flow_one_day_at_5,

    MEAN(rec_to_sale_flow_one_day_at_10) AS mean_rec_to_sale_flow_one_day_at_10,
    MIN(rec_to_sale_flow_one_day_at_10) AS min_rec_to_sale_flow_one_day_at_10,
    MAX(rec_to_sale_flow_one_day_at_10) AS max_rec_to_sale_flow_one_day_at_10,

    MEAN(rec_to_sale_flow_fourteen_days_at_3) AS mean_rec_to_sale_flow_fourteen_days_at_3,
    MIN(rec_to_sale_flow_fourteen_days_at_3) AS min_rec_to_sale_flow_fourteen_days_at_3,
    MAX(rec_to_sale_flow_fourteen_days_at_3) AS max_rec_to_sale_flow_fourteen_days_at_3,

    MEAN(rec_to_sale_flow_fourteen_days_at_5) AS mean_rec_to_sale_flow_fourteen_days_at_5,
    MIN(rec_to_sale_flow_fourteen_days_at_5) AS min_rec_to_sale_flow_fourteen_days_at_5,
    MAX(rec_to_sale_flow_fourteen_days_at_5) AS max_rec_to_sale_flow_fourteen_days_at_5,

    MEAN(rec_to_sale_flow_fourteen_days_at_10) AS mean_rec_to_sale_flow_fourteen_days_at_10,
    MIN(rec_to_sale_flow_fourteen_days_at_10) AS min_rec_to_sale_flow_fourteen_days_at_10,
    MAX(rec_to_sale_flow_fourteen_days_at_10) AS max_rec_to_sale_flow_fourteen_days_at_10,

    MEAN(rec_to_rent_flow_one_day_at_3) AS mean_rec_to_rent_flow_one_day_at_3,
    MIN(rec_to_rent_flow_one_day_at_3) AS min_rec_to_rent_flow_one_day_at_3,
    MAX(rec_to_rent_flow_one_day_at_3) AS max_rec_to_rent_flow_one_day_at_3,

    MEAN(rec_to_rent_flow_one_day_at_5) AS mean_rec_to_rent_flow_one_day_at_5,
    MIN(rec_to_rent_flow_one_day_at_5) AS min_rec_to_rent_flow_one_day_at_5,
    MAX(rec_to_rent_flow_one_day_at_5) AS max_rec_to_rent_flow_one_day_at_5,

    MEAN(rec_to_rent_flow_one_day_at_10) AS mean_rec_to_rent_flow_one_day_at_10,
    MIN(rec_to_rent_flow_one_day_at_10) AS min_rec_to_rent_flow_one_day_at_10,
    MAX(rec_to_rent_flow_one_day_at_10) AS max_rec_to_rent_flow_one_day_at_10,

    MEAN(rec_to_rent_flow_seven_days_at_3) AS mean_rec_to_rent_flow_seven_days_at_3,
    MIN(rec_to_rent_flow_seven_days_at_3) AS min_rec_to_rent_flow_seven_days_at_3,
    MAX(rec_to_rent_flow_seven_days_at_3) AS max_rec_to_rent_flow_seven_days_at_3,

    MEAN(rec_to_rent_flow_seven_days_at_5) AS mean_rec_to_rent_flow_seven_days_at_5,
    MIN(rec_to_rent_flow_seven_days_at_5) AS min_rec_to_rent_flow_seven_days_at_5,
    MAX(rec_to_rent_flow_seven_days_at_5) AS max_rec_to_rent_flow_seven_days_at_5,

    MEAN(rec_to_rent_flow_seven_days_at_10) AS mean_rec_to_rent_flow_seven_days_at_10,
    MIN(rec_to_rent_flow_seven_days_at_10) AS min_rec_to_rent_flow_seven_days_at_10,
    MAX(rec_to_rent_flow_seven_days_at_10) AS max_rec_to_rent_flow_seven_days_at_10,

    dt_rec_received

FROM
    datalake_recommendations.recommendation_metrics_agg_recset
GROUP BY
    dt_rec_received,
    business_context,
    display_type
