SELECT
    CAST(DATE_FORMAT(CAST(date AS DATE),'yyyyMMdd') AS INTEGER) AS id_date,
    city_group,
    CAST(REPLACE(prospects,',','') AS FLOAT) AS prospects,
    CAST(REPLACE(qualifieds,',','') AS FLOAT) AS qualifieds,
    concat_cost,
    concat_prospects,
    concat_qualifieds,
    supply_channel,
    supply_medium,
    supply_origin,
    supply_source,
    concat_date,
    CAST(tier AS INTEGER) AS tier,
    CAST(REPLACE(cost_per_source,',','') AS FLOAT) AS cost_per_source,
    CAST(week_start AS DATE) AS dt_week_started,
    CAST(quarter AS INTEGER) AS quarter,
    CAST(halfyear AS INTEGER) AS halfyear,
    CAST(month AS INTEGER) AS month,
    CAST(date AS DATE) AS dt_target
FROM
    datalake_gsheets_raw.base_supply_souce_for_sale