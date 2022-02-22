SELECT
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    target_nau,
    budget,
    target_nu,
    target_oau,
    new_target_nau,
    DATE(data) AS dt_target
FROM
    datalake_gsheets_raw.affiliates_acquisition_targets