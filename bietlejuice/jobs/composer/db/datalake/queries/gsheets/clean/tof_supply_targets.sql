SELECT
    NULLIF(city_group,'') AS city_group,
    NULLIF(INT(tier),'') AS tier,
    NULLIF(supply_origin,'') AS supply_origin,
    NULLIF(supply_channel,'') AS supply_channel,
    NULLIF(supply_medium,'') AS supply_medium,
    NULLIF(supply_source,'') AS supply_source,
    NULLIF(FLOAT(traffic),'') AS traffic,
    NULLIF(FLOAT(leads),'') AS leads,
    NULLIF(DATE(date),'') AS dt_target,
    NULLIF(DATE(week_start),'') AS dt_week,
    NULLIF(INT(month),'') AS month,
    NULLIF(INT(quarter),'') AS quarter,
    NULLIF(INT(half_year),'') AS half_year
FROM
    datalake_gsheets_raw.tof_supply_targets
