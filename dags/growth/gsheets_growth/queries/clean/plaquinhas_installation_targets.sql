SELECT
    NULLIF(business_context,'') AS business_context,
    NULLIF(city_group,'') AS city_group,
    NULLIF(listing_type,'') AS listing_type,
    NULLIF(FLOAT(new_installed_plaquinhas_target),'') AS new_installed_plaquinhas_target,
    NULLIF(TO_DATE(date, "dd/MM/yy"),'') AS dt_target
FROM
    datalake_gsheets_raw.plaquinhas_installation_targets