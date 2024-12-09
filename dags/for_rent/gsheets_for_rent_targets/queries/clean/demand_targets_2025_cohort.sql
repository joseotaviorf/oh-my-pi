SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(rental_administrator, '') AS rental_administrator,
    NULLIF(business_type, '') AS business_type,
    NULLIF(rent_flow_origin, '') AS rent_flow_origin,
    NULLIF(weeks_conversion, '') AS weeks_conversion,
    CAST(REPLACE(NULLIF(vb2os, ''), ',', '') AS FLOAT) AS vb2os,
    CAST(REPLACE(NULLIF(os2oa, ''), ',', '') AS FLOAT) AS os2oa,
    CAST(REPLACE(NULLIF(oa2ca, ''), ',', '') AS FLOAT) AS oa2ca,
    CAST(REPLACE(NULLIF(ca2cs, ''), ',', '') AS FLOAT) AS ca2cs,
    CAST(REPLACE(NULLIF(cs, ''), ',', '') AS FLOAT) AS cs,
    CAST(REPLACE(NULLIF(vb2vc, ''), ',', '') AS FLOAT) AS vb2vc,
    CAST(REPLACE(NULLIF(vc2os, ''), ',', '') AS FLOAT) AS vc2os,
    CAST(NULLIF(week_start, '') AS DATE) AS week_start
FROM
    datalake_gsheets_raw.demand_targets_2025_cohort
    						