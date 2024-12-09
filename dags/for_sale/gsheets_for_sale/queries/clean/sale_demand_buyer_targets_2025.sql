SELECT
    NULLIF(region, '') AS region,
    NULLIF(price_range, '') AS price_range,
    CAST(NULLIF(is_tqc, '') AS BOOLEAN) AS is_tqc,
    NULLIF(modelo, '') AS modelo,
    CAST(REPLACE(NULLIF(bp, ''), ',', '') AS FLOAT) AS bp,
    CAST(REPLACE(NULLIF(bp_w_vc, ''), ',', '') AS FLOAT) AS bp_w_vc,
    CAST(REPLACE(NULLIF(bp_w_os, ''), ',', '') AS FLOAT) AS bp_w_os,
    CAST(REPLACE(NULLIF(bp_w_oa, ''), ',', '') AS FLOAT) AS bp_w_oa,
    CAST(REPLACE(NULLIF(bp_w_ccv, ''), ',', '') AS FLOAT) AS bp_w_ccv,
    CAST(REPLACE(NULLIF(vb, ''), ',', '') AS FLOAT) AS vb,
    CAST(REPLACE(NULLIF(vc, ''), ',', '') AS FLOAT) AS vc,
    CAST(REPLACE(NULLIF(os, ''), ',', '') AS FLOAT) AS os,
    CAST(REPLACE(NULLIF(oa, ''), ',', '') AS FLOAT) AS oa,
    CAST(REPLACE(NULLIF(ccv, ''), ',', '') AS FLOAT) AS ccv,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.sale_demand_buyer_targets_2025