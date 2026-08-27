SELECT
    id,
    status,
    file_storage_type,
    file_storage_identifier,
    display_title,
    owner_resource,
    owner_resource_id,
    CAST(deleted AS BOOLEAN) AS is_deleted,
    created_on AS ts_created,
    updated_on AS ts_updated,
    year,
    month,
    day
FROM
    datalake_mission_control_raw.filestorage
