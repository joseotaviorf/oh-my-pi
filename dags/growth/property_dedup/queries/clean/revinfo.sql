SELECT 
    rev,
    dt AS dt_rev,
    year,
    month,
    day
FROM 
    datalake_property_dedup_raw.revinfo
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY rev ORDER BY dt DESC) = 1