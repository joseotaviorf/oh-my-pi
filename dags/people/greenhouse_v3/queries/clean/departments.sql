SELECT
    -- ids
    id AS id_department,
    parent_id AS id_parent,
    external_id AS id_external,
    -- text fields
    name,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.departments
