SELECT
    NULLIF(city_group,'') AS city_group,
    NULLIF(channel,'') AS channel,
    NULLIF(FLOAT(visits_booked_target),'') AS visits_booked_target,
    NULLIF(DATE(date),'') AS dt_target
FROM
    datalake_gsheets_raw.plaquinhas_demand_targets