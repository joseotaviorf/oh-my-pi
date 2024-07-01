SELECT
    id,
    field_id AS id_field,
    label,
    "position",
    enabled AS is_enabled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.field_choices
WHERE  
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')