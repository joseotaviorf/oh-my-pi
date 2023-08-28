SELECT
    CAST(NULLIF(company, '') AS STRING) AS company,
    CAST(NULLIF(city_group,'') AS STRING) AS city_group,
    CAST(NULLIF(lead_context,'') AS STRING) AS lead_context,
    CAST(NULLIF(supply_channel,'') AS STRING) AS supply_channel,
    CAST(NULLIF(supply_origin,'') AS STRING) AS supply_origin,
    CAST(NULLIF(prospects, '') AS DOUBLE) AS prospects,
    CAST(NULLIF(qualifieds, '') AS DOUBLE) AS qualifieds,
    CAST(NULLIF(available_qualifieds, '') AS DOUBLE) AS available_qualifieds,
    CAST(NULLIF(opportunities, '') AS DOUBLE) AS opportunities,
    CAST(NULLIF(first_listings, '') AS DOUBLE) AS first_listings,
    CAST(NULLIF(is_expansion,'') AS STRING) AS is_expansion,
    CAST(NULLIF(is_new_business,'') AS STRING) AS is_new_business,
    CAST(NULLIF(dt_target, '') AS DATE) AS dt_target,
    CAST(NULLIF(dt_week_started, '') AS DATE) AS dt_week_started,
    CAST(NULLIF(month, '') AS DATE) AS month,
    CAST(NULLIF(quarter, '') AS DATE) AS quarter,
    CAST(NULLIF(year, '') AS DATE) AS year
FROM
    datalake_gsheets_raw.target_supply_historical_sale
