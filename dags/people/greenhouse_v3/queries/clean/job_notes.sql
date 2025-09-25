SELECT
    id,
    user_id AS id_user,
    job_id AS id_job,
    body,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    visibility,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.job_notes
    