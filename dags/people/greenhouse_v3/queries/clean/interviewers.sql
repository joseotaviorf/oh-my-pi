WITH ranked_interviewers AS (
    SELECT
        id,
        interview_id AS id_interview,
        user_id AS id_user,
        scorecard_id AS id_scorecard,
        response_status,
        email,
        CAST(created_at AS TIMESTAMP) AS ts_created,
        CAST(updated_at AS TIMESTAMP) AS ts_updated,
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
        datalake_greenhouse_v3_raw.interviewers
    WHERE
        MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
        AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')
)
SELECT
    id,
    id_interview,
    id_user,
    id_scorecard,
    response_status,
    email,
    ts_created,
    ts_updated,
    ts_load,
    year,
    month,
    day
FROM
    ranked_interviewers
WHERE
    rn = 1
