SELECT
    code AS id,
    `name` AS locale_name,
    active AS is_active,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM
    datalake_hogwarts_raw.locale