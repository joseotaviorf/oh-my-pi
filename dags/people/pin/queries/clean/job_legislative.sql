SELECT
    job_leg_id AS id_job_legislative,
    business_group_id AS id_business_group,
    job_id AS id_job,
    action_occurrence_id AS id_action_occurrence,
    legislation_code,
    information1 AS brazilian_occupation_code,
    created_by,
    last_updated_by AS updated_by,
    INT(sequence_number) AS sequence_number,
    INT(object_version_number) AS object_version_number,
    TO_DATE(effective_start_date) AS dt_effective_started,
    COALESCE(NULLIF(TO_DATE(effective_end_date), DATE('4712-12-31')), DATE('9999-12-31')) AS dt_effective_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_job_leg_f