SELECT
    city_group,
    mkt_origin,
    mkt_vertical,
    CAST(REPLACE(budget, ',', '') AS FLOAT) AS budget,
    CAST(REPLACE(prospects_target,',','') AS FLOAT) AS prospects_target,
    CAST(week_start AS DATE) AS dt_week_started,
    CAST(date AS DATE) AS dt_target
FROM
    datalake_gsheets_raw.marketing_affiliates_targets_replanning