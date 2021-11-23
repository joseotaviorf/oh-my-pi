SELECT
    NULLIF(City_group,'') as city_group,
    NULLIF(Mkt_channel,'') as mkt_channel,
    NULLIF(Mkt_medium,'') as mkt_medium,
    NULLIF(Mkt_source,'') as mkt_source,
    CAST(REPLACE(Monthly_target, ',', '') AS FLOAT) AS tof_monthly_target,
    NULLIF(Month,'') as month_target
FROM
    datalake_gsheets_raw.targets_casa_mineira_tof_monthly