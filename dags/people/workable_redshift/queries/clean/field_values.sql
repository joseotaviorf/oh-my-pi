SELECT
    id,
    resource_id AS id_resource,
    field_id AS id_field,
    member_id AS id_member,
    `type`,
    resource_type,
    `data`,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.field_values