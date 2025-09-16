SELECT
    id,
    `name`,
    `default` AS is_default,
    base AS is_base,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.pipelines