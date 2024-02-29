SELECT
    id AS sk_follow_up_tag,
    category,
    description,
    is_positive,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.feedback_tag
