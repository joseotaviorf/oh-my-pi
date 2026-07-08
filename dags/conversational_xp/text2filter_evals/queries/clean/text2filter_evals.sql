WITH ranked_evals AS (
    SELECT
        uuid,
        ts_log,
        user_query,
        current_filters,
        extracted_filters,
        score,
        comment,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY uuid
            ORDER BY year DESC, month DESC, day DESC, ts_log DESC
        ) AS rn
    FROM
        datalake_text2filter_evals_raw.text2filter_evals
)
SELECT
    uuid,
    ts_log,
    user_query,
    current_filters,
    extracted_filters,
    score,
    comment,
    year,
    month,
    day
FROM
    ranked_evals
WHERE
    rn = 1
