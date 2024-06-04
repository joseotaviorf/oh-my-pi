SELECT
    city_group,
    hub_offer,
    weeks_conversion,
    CAST(REPLACE(vb2vc, ',', '') AS DECIMAL(16,4)) AS vb2vc,
    CAST(REPLACE(vc2os, ',', '') AS DECIMAL(16,4)) AS vc2os,
    CAST(REPLACE(os2oa, ',', '') AS DECIMAL(16,4)) AS os2oa,
    CAST(REPLACE(oa2ccv, ',', '') AS DECIMAL(16,4)) AS oa2ccv,
    CAST(REPLACE(ccv_signed, ',', '') AS DECIMAL(16,4)) AS ccv_signed,
    CAST(REPLACE(os2ccv, ',', '') AS DECIMAL(16,4)) AS os2ccv,
    is_rede,
    TO_DATE(week_start, 'yyyy-MM-dd') AS dt_week_started
FROM
    datalake_gsheets_raw.sale_demand_cohort_budget_2024
