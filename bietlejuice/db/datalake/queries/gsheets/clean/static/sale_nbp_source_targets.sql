SELECT
    city_group,
    context,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    nbp_target,
    rbp_target,
    week_start,
    month,
    year,
    date AS dt_target
FROM
    datalake_gsheets_raw.sale_nbp_source_targets
