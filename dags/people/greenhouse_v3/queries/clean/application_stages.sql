SELECT
    -- ids
    id,
    application_id AS id_application,
    job_interview_stage_id AS id_job_interview_stage,
    -- numeric
    days_in_stage,
    -- boolean
    CAST(current AS BOOLEAN) AS is_current,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(entered_at AS TIMESTAMP) AS ts_entered,
    CAST(exited_at AS TIMESTAMP) AS ts_exited,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.application_stages
WHERE
    MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
    AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')