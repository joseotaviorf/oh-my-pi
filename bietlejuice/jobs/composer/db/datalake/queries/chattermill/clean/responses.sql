SELECT
    id,
    score,
    comment,
    original_comment,
    user_attributes,
    data_type,
    data_source,
    dataset,
    tags,
    themes,
    created_at,
    updated_at,
    year,
    month,
    day
FROM
    datalake_chattermill_raw.responses
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
