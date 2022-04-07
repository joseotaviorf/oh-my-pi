SELECT
    business_context,
    city_group,
    CAST(REPLACE(tier, ',', '') AS INT) AS tier,
    CAST(REPLACE(depublications, ',', '') AS DECIMAL(14,6)) AS depublications,  
    CAST(REPLACE(ongoing_listings, ',', '') AS DECIMAL(14,6)) AS ongoing_listings,  
    CAST(REPLACE(recovered, ',', '') AS DECIMAL(14,6)) AS recovered,  
    CAST(REPLACE(relisting, ',', '') AS DECIMAL(14,6)) AS relisting,  
    CAST(REPLACE(relistings_recovered, ',', '') AS DECIMAL(14,6)) AS relistings_recovered,  
    CAST(REPLACE(suspensions, ',', '') AS DECIMAL(14,6)) AS suspensions,  
    TO_DATE(date, 'yyyy-M-d') AS dt_created,
    TO_DATE(week_start, 'yyyy-M-d') AS dt_week_start,
    CAST(year AS INT) AS year,
    CAST(halfyear AS INT) AS semester,
    CAST(quarter AS INT) AS quarter,
    CAST(month AS INT) AS month
FROM
    datalake_gsheets_raw.ongoing_listings_targets;
