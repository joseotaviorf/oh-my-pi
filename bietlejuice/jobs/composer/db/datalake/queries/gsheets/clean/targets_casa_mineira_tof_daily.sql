SELECT
    NULLIF(City_group,'') as city_group,
    NULLIF(Mkt_channel,'') as mkt_channel,
    NULLIF(Mkt_medium,'') as mkt_medium,
    NULLIF(Mkt_source,'') as mkt_source,
    CAST(replace(Daily_target, ',', '') AS FLOAT) AS tof_daily_target,
    NULLIF(Week,'') as week_start,
    CAST(NULLIF(Day,'') AS DATE) as dt_target
FROM
    datalake_gsheets_raw.targets_casa_mineira_tof_daily