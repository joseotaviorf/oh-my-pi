SELECT
    -- ids
    id,
    parent_id AS id_parent,
    external_id AS id_external,
    parent_office_external_id AS id_parent_office_external,
    -- text fields
    name,
    location.name AS location_name,
    -- timestamps
    NOW() AS ts_load,
    -- arrays
    child_ids,
    child_office_external_ids,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.offices