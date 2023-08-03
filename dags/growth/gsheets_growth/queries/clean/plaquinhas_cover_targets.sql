SELECT
    NULLIF(business_context,'') AS business_context,
    NULLIF(city_group,'') AS city_group,
    NULLIF(FLOAT(ongoing_listings_target),'') AS ongoing_listings_target,
    NULLIF(FLOAT(active_plaquinhas_target),'') AS active_plaquinhas_target,
    NULLIF(TO_DATE(date, "dd/MM/yy"),'') AS dt_target
FROM
    datalake_gsheets_raw.plaquinhas_cover_targets