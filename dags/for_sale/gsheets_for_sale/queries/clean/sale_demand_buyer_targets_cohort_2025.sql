SELECT
    NULLIF(region, '') AS region,
    NULLIF(price_range, '') AS price_range,
    CAST(NULLIF(is_tqc, '') AS BOOLEAN) AS is_tqc,
    NULLIF(modelo, '') AS modelo,
    NULLIF(week_origin, '') AS week_origin,
    CAST(REPLACE(NULLIF(bp2bp_w_vc, ''), ',', '') AS FLOAT) AS bp2bp_w_vc,
    CAST(REPLACE(NULLIF(bp_w_vc2bp_w_os, ''), ',', '') AS FLOAT) AS bp_w_vc2bp_w_os,
    CAST(REPLACE(NULLIF(bp_w_os2bp_w_oa, ''), ',', '') AS FLOAT) AS bp_w_os2bp_w_oa,
    CAST(REPLACE(NULLIF(bp_w_oa2bp_w_ccv, ''), ',', '') AS FLOAT) AS bp_w_oa2bp_w_ccv,
    CAST(REPLACE(NULLIF(bp_w_ccv, ''), ',', '') AS FLOAT) AS bp_w_ccv,
    CAST(NULLIF(week_start, '') AS DATE) AS week_start
FROM
    datalake_gsheets_raw.sale_demand_buyer_targets_cohort_2025

    				