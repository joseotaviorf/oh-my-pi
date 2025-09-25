SELECT
    id,
    job_id AS id_job,
    name,
    CAST(sort_order AS INT) AS sort_order,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(active AS BOOLEAN) AS is_active,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.job_interview_stages