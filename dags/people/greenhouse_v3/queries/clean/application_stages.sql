WITH ranked_application_stages AS (
    SELECT
        id,
        application_id AS id_application,
        job_interview_stage_id AS id_job_interview_stage,
        days_in_stage,
        CAST(current AS BOOLEAN) AS is_current,
        CAST(created_at AS TIMESTAMP) AS ts_created,
        CAST(updated_at AS TIMESTAMP) AS ts_updated,
        CAST(entered_at AS TIMESTAMP) AS ts_entered,
        CAST(exited_at AS TIMESTAMP) AS ts_exited,
        NOW() AS ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY
                CAST(updated_at AS TIMESTAMP) DESC NULLS LAST,
                CAST(created_at AS TIMESTAMP) DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS rn
    FROM
        datalake_greenhouse_v3_raw.application_stages
    WHERE
        MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
        AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')
)
SELECT
    id,
    id_application,
    id_job_interview_stage,
    days_in_stage,
    is_current,
    ts_created,
    ts_updated,
    ts_entered,
    ts_exited,
    ts_load,
    year,
    month,
    day
FROM
    ranked_application_stages
WHERE
    rn = 1
