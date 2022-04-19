SELECT
    campaign,
    city_group,
    CAST(first_listings AS FLOAT) AS first_listings,
    mkt_channel,
    mkt_origin,
    mkt_type,
    operacao,
    CAST(opportunities AS FLOAT) AS opportunities,
    CAST(prospects AS FLOAT) AS prospects,
    CAST(qualifieds AS FLOAT) AS qualifieds,
    CAST(halfyear AS INTEGER) AS halfyear,
    CAST(quarter AS INTEGER) AS quarter,
    CAST(year AS INTEGER) AS year,
    CAST(month AS INTEGER) AS month,
    TO_DATE(week, 'yyyy-MM-dd') AS dt_week,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.sale_supply_targets
