SELECT
    id,
    job_id AS id_job,
    job_title,
    type AS question_type,
    body,
    position,
    enabled AS is_enabled,
    rejecting AS has_automatic_rejection_enabled,
    required AS is_required,
    question_created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_workable_redshift_raw.questions
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)