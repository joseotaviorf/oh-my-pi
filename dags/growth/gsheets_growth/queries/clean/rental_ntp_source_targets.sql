SELECT
    tier,
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    ntp_target,
    rtp_target,
    week_start,
    month,
    year,
    date AS dt_target
FROM
    datalake_gsheets_raw.rental_ntp_source_targets