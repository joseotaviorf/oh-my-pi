SELECT
    city_group,
    first_listings,
    lead_context,
    opportunities,
    prospects,
    qualifieds,
    supply_channel,
    supply_origin,
    top_of_funnel,
    CAST(tier AS INTEGER) AS tier,
    CAST(halfyear AS INTEGER) AS halfyear,
    CAST(quarter AS INTEGER) AS quarter,
    CAST(month AS INTEGER) AS month,
    CAST(year AS INTEGER) AS year,
    TO_DATE(week_start, 'yyyy-MM-dd') AS dt_week_started,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.supply_targets_2022_mx