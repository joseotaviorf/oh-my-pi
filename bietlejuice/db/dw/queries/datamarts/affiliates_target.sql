SELECT
    day::bigint,
    indicaai_target_listings::bigint,
    doorman_target_listings::bigint,
    indicaai_target_leads::bigint,
    doorman_target_leads::bigint,
    current_timestamp as ts_load
FROM
    datalake_raw.affiliates_target
