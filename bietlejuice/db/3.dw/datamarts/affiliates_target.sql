SELECT
    day::bigint,
    indicaai_target_listings::bigint,
    doorman_target_listings::bigint,
    indicaai_target_leads::bigint,
    doorman_target_leads::bigint
FROM
    datalake_raw.affiliates_target