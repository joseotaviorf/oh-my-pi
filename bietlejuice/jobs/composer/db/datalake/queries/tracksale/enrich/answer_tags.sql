WITH unnested_tags AS (
    SELECT
        id AS id_answer,
        ts_answer_sent_local,
        EXPLODE(FROM_JSON(tags,'array<string>')) AS tag
    FROM datalake_tracksale.answer
)
SELECT
    id_answer,
    ts_answer_sent_local,
    GET_JSON_OBJECT(tag, '$.name') AS tag_name,
    GET_JSON_OBJECT(tag, '$.value') AS tag_value
FROM unnested_tags