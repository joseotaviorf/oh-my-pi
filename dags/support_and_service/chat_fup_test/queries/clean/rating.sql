SELECT
    id AS id_rating,
    id_origin,
    user_id AS id_user,
    evaluated_tool,
    csat_version,
    channel,
    grade,
    comment,
    meta,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_chat_fup_test_raw.rating
