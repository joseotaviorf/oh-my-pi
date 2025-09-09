SELECT
    -- ids
    id,

    -- non-metrics
    code_generation,
    code_prefix,
    TO_JSON(meta) AS meta,

    -- metrics
    active AS is_active,
    CAST(code_seed AS BIGINT) AS code_seed,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.requisition_templates
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)