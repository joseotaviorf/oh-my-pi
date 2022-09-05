WITH cohorts_20w_direct_rates AS (
    SELECT
        wr_1w.id_cohort_listing,
        wr_1w.city_group,
        wr_1w.consultant_type,
        wr_1w.entry_condition,
        wr_1w.exclusivity,
        wr_1w.hybrid,
        wr_1w.listing_category_start,
        wr_1w.mkt_completion,
        wr_1w.mkt_origin,
        wr_1w.depub_w AS depub_1w,
        wr_1w.imoveis_w AS imoveis_1w,
        wr_1w.list_w_cs_w AS list_w_cs_1w,
        wr_1w.suspenso_w AS suspenso_1w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_1w.list_w_cs_w/wr_1w.imoveis_w) AS l2r_1w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_1w.suspenso_w/wr_1w.imoveis_w) AS l2s_1w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_1w.depub_w/wr_1w.imoveis_w) AS l2u_1w,
        wr_4w.depub_w AS depub_4w,
        wr_4w.imoveis_w AS imoveis_4w,
        wr_4w.list_w_cs_w AS list_w_cs_4w,
        wr_4w.suspenso_w AS suspenso_4w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_4w.list_w_cs_w/wr_1w.imoveis_w) AS l2r_4w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_4w.suspenso_w/wr_1w.imoveis_w) AS l2s_4w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_4w.depub_w/wr_1w.imoveis_w) AS l2u_4w,
        wr_8w.depub_w AS depub_8w,
        wr_8w.imoveis_w AS imoveis_8w,
        wr_8w.list_w_cs_w AS list_w_cs_8w,
        wr_8w.suspenso_w AS suspenso_8w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_8w.list_w_cs_w/wr_1w.imoveis_w) AS l2r_8w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_8w.suspenso_w/wr_1w.imoveis_w) AS l2s_8w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_8w.depub_w/wr_1w.imoveis_w) AS l2u_8w,
        wr_16w.depub_w AS depub_16w,
        wr_16w.imoveis_w AS imoveis_16w,
        wr_16w.list_w_cs_w AS list_w_cs_16w,
        wr_16w.suspenso_w AS suspenso_16w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_16w.list_w_cs_w/wr_1w.imoveis_w) AS l2r_16w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_16w.suspenso_w/wr_1w.imoveis_w) AS l2s_16w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_16w.depub_w/wr_1w.imoveis_w) AS l2u_16w,
        wr_20w.depub_w AS depub_20w,
        wr_20w.imoveis_w AS imoveis_20w,
        wr_20w.list_w_cs_w AS list_w_cs_20w,
        wr_20w.suspenso_w AS suspenso_20w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_20w.list_w_cs_w/wr_1w.imoveis_w) AS l2r_20w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_20w.suspenso_w/wr_1w.imoveis_w) AS l2s_20w,
        IF(wr_1w.imoveis_w = 0, 0, 1.0*wr_20w.depub_w/wr_1w.imoveis_w) AS l2u_20w,
        wr_1w.dt_listing_month_started,
        wr_1w.dt_listing_week_started
    FROM
        datalake_rental_listing_metrics.cohort_listings_weekly AS wr_1w
    LEFT JOIN 
        datalake_rental_listing_metrics.cohort_listings_weekly AS wr_4w
            ON wr_1w.id_cohort_listing = wr_4w.id_cohort_listing
            AND wr_4w.weeks_since_listing_started = 4
    LEFT JOIN
        datalake_rental_listing_metrics.cohort_listings_weekly AS wr_8w
            ON wr_1w.id_cohort_listing = wr_8w.id_cohort_listing
            AND wr_8w.weeks_since_listing_started = 8
    LEFT JOIN
        datalake_rental_listing_metrics.cohort_listings_weekly AS wr_16w
            ON wr_1w.id_cohort_listing = wr_16w.id_cohort_listing
            AND wr_16w.weeks_since_listing_started = 16
    LEFT JOIN
        datalake_rental_listing_metrics.cohort_listings_weekly AS wr_20w
            ON wr_1w.id_cohort_listing = wr_20w.id_cohort_listing
            AND wr_20w.weeks_since_listing_started = 20
    WHERE
        wr_1w.weeks_since_listing_started = 1
)
SELECT
    id_cohort_listing,
    city_group,
    consultant_type,
    entry_condition,
    exclusivity,
    hybrid,
    listing_category_start,
    mkt_completion,
    mkt_origin,
    depub_1w,
    imoveis_1w,
    list_w_cs_1w,
    suspenso_1w,
    l2r_1w,
    l2s_1w,
    l2u_1w,
    IF(l2r_1w = 0, 0, (l2s_1w + l2u_1w)/(l2s_1w + l2u_1w + l2r_1w)) AS churn_1w,
    depub_4w,
    imoveis_4w,
    list_w_cs_4w,
    suspenso_4w,
    l2r_4w,
    l2s_4w,
    l2u_4w,
    IF(l2r_4w = 0, 0, (l2s_4w + l2u_4w)/(l2s_4w + l2u_4w + l2r_4w)) AS churn_4w,
    depub_8w,
    imoveis_8w,
    list_w_cs_8w,
    suspenso_8w,
    l2r_8w,
    l2s_8w,
    l2u_8w,
    IF(l2r_8w = 0, 0, (l2s_8w + l2u_8w)/(l2s_8w + l2u_8w + l2r_8w)) AS churn_8w,
    depub_16w,
    imoveis_16w,
    list_w_cs_16w,
    suspenso_16w,
    l2r_16w,
    l2s_16w,
    l2u_16w,
    IF(l2r_16w = 0, 0, (l2s_16w + l2u_16w)/(l2s_16w + l2u_16w + l2r_16w)) AS churn_16w,
    depub_20w,
    imoveis_20w,
    list_w_cs_20w,
    suspenso_20w,
    l2r_20w,
    l2s_20w,
    l2u_20w,
    IF(l2r_20w = 0, 0, (l2s_20w + l2u_20w)/(l2s_20w + l2u_20w + l2r_20w)) AS churn_20w,
    dt_listing_month_started,
    dt_listing_week_started
FROM
    cohorts_20w_direct_rates