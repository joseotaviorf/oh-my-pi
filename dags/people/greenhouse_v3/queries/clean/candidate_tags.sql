SELECT
    -- ids
    id AS id_candidate_tag,
    -- text fields
    name,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.candidate_tags
