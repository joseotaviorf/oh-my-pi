SELECT
    code AS id,
    tagging_class,
    active AS is_active,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM
    datalake_hogwarts_raw.tagging_category