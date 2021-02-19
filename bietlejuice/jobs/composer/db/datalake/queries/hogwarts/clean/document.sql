SELECT
    code AS id,
    scope,
    active AS is_active,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM 
    datalake_hogwarts_raw.document