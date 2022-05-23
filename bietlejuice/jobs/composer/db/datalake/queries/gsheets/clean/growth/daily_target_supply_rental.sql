SELECT
    CAST(DATE_FORMAT(CAST(date AS DATE),'yyyymmdd') AS INTEGER) AS id_date,
    concat_cost,
    concat_prospects,
    concat_qualifieds,
    concat_date,
    CAST(REPLACE(cost_per_source,',','') AS FLOAT) AS cost_per_source,
    CAST(REPLACE(prospects,',','') AS FLOAT) AS prospects,
    CAST(REPLACE(qualifieds,',','') AS FLOAT) AS qualifieds,
    city_group,
    supply_channel,
    supply_medium,
    supply_origin,
    supply_source,
    CAST(tier AS INTEGER) AS tier,
    CAST(week_start AS DATE) AS dt_week_started,
    CAST(quarter AS INTEGER) AS quarter,
    CAST(halfyear AS INTEGER) AS halfyear,
    CAST(month AS INTEGER) AS month,
    CAST(date AS DATE) AS dt_target
FROM
    datalake_gsheets_raw.base_supply_souce_for_rent