SELECT
    id,
    job_interview_stage_id AS id_job_interview_stage,
    job_id AS id_job,
    name,
    scheduling_type,
    CAST(duration AS INT) AS duration_minutes,
    CAST(sort_order AS INT) AS sort_order,
    summary,
    instructions,
    CAST(active AS BOOLEAN) AS is_active,
    CAST(require_scorecard AS BOOLEAN) AS is_scorecard_required,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.job_interviews
