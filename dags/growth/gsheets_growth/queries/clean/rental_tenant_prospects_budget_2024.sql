SELECT
    tier,
    city_group,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(REPLACE(ntp_target, ',', '') AS DECIMAL(16,4)) AS ntp_target,
    CAST(REPLACE(rtp_target, ',', '') AS DECIMAL(16,4)) AS rtp_target,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.rental_tenant_prospects_budget_2024