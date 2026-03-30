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
    datalake_text2filter_evals_raw.text2filter_evals
WHERE
    MAKE_DATE(year, month, day) = MAKE_DATE({year}, {month}, {day})
