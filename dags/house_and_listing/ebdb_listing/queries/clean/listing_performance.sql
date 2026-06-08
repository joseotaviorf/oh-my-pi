SELECT
    id,
    listing_business_context_id AS id_listing_business_context,
    traffic_count,
    visits_scheduled_count,
    offers_count,
    favorites_count,
    traffic_median,
    visits_scheduled_median,
    offers_median,
    favorites_median,
    score_value,
    period_in_days,
    traffic_flag,
    visits_scheduled_flag,
    offers_flag,
    favorites_flag,
    score_type,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.ListingPerformance
