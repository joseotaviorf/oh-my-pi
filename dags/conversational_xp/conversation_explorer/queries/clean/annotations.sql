SELECT
    annotation_id,
    id_langfuse_session,
    annotation_text,
    author,
    created_at,
    year,
    month,
    day
FROM
    datalake_conversation_explorer_raw.annotations
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') - INTERVAL 1 DAY AND DATE('{load_end_date}')
