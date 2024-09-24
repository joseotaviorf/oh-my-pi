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
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)