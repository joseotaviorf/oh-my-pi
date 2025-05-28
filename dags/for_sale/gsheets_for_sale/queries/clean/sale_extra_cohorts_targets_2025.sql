SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(is_ht, '') AS is_ht,
    NULLIF(is_tqc, '') AS is_tqc,
    NULLIF(modelo, '') AS modelo,
    NULLIF(month_conversion, '') AS month_conversion,
    CAST(REPLACE(NULLIF(bp2bp_w_os, ''), ',', '') AS FLOAT) AS bp2bp_w_os,
    CAST(REPLACE(NULLIF(bp_w_os2bp_w_ccv, ''), ',', '') AS FLOAT) AS bp_w_os2bp_w_ccv,
    CAST(REPLACE(NULLIF(bp2bp_w_ccv, ''), ',', '') AS FLOAT) AS bp2bp_w_ccv,
    CAST(NULLIF(month_start, '') AS DATE) AS month_start
FROM
    datalake_gsheets_raw.sale_extra_cohorts_targets_2025