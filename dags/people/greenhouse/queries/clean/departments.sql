SELECT
    -- ids
    id,
    parent_id AS id_parent,
    external_id AS id_external,
    -- text fields
    name,
    -- timestamps
    NOW() AS ts_load,
    -- arrays
    child_ids,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.departments
