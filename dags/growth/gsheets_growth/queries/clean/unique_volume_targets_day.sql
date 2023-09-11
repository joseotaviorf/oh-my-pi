SELECT
    CAST(NULLIF(city_group, '') AS STRING) AS city_group,
    CAST(NULLIF(supply_channel,'') AS STRING) AS supply_channel,
    CAST(NULLIF(supply_medium,'') AS STRING) AS supply_medium,    
    CAST(NULLIF(supply_origin,'') AS STRING) AS supply_origin,
    CAST(NULLIF(prospects, '') AS DOUBLE) AS prospects,
    CAST(NULLIF(qualifieds, '') AS DOUBLE) AS qualifieds,
    CAST(NULLIF(opportunities, '') AS DOUBLE) AS opportunities,
    CAST(NULLIF(first_listings, '') AS DOUBLE) AS first_listings,
    CAST(NULLIF(date, '') AS DATE) AS date,
    CAST(NULLIF(month, '') AS INTEGER) AS month,
    CAST(NULLIF(quarter, '') AS DATE) AS quarter,
    CAST(NULLIF(halfyear, '') AS DATE) AS half_year,
    CAST(NULLIF(week_start, '') AS DATE) AS week_start,
FROM
    datalake_gsheets_raw.unique_volume_targets_day
