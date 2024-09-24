SELECT
    id,
    stage_id AS id_stage,
    job_id AS id_job,
    candidate_id AS id_candidate,
    member_id AS id_member,
    trackable_id AS id_trackable,
    target_stage_id AS id_target_stage,
    `action`,
    action_type,
    stage_kind,
    job_title,
    job_department,
    candidate_name,
    member_name,
    trackable_type,
    member_is_recruiter AS is_member_recruiter,
    activity_created_at AS ts_activity_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.activities
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)