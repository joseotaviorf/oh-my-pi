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
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.job_locations