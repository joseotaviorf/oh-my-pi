SELECT
    NULLIF(city_group,'') AS city_group,
    NULLIF(listing_type,'') AS listing_type,
    NULLIF(FLOAT(new_installed_plaquinhas_target),'') AS new_installed_plaquinhas_target,
    NULLIF(FLOAT(active_plaquinhas_target),'') AS active_plaquinhas_target,
    NULLIF(FLOAT(cover_percent_target),'') AS cover_percent_target,
    NULLIF(DATE(date),'') AS dt_target
FROM
    datalake_gsheets_raw.plaquinhas_installation_targets