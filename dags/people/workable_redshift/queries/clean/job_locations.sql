SELECT
    -- ids
    id,
    job_id AS id_job,
    location_id AS id_location,

    -- non-metrics
    zip_code,
    position,

    -- metrics (booleans)
    hidden AS is_hidden,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.job_locations
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)