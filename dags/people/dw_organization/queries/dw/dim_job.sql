SELECT
    id_job AS sk_job,
    job_name,
    job_family,
    career_track,
    is_active,
    CAST(dt_valid_from AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_people.job_with_salary_table
WHERE
    is_current = TRUE
