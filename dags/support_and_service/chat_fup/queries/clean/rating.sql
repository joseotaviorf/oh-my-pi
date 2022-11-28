SELECT
    id as id_rating,
    id_origin,
    user_id as id_user,
    evaluated_tool,
    csat_version,
    channel,
    grade,
    comment,
    meta,
    created_at as ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_chat_fup_raw.rating
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
