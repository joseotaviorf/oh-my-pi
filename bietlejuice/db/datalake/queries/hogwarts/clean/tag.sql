SELECT
    code AS id, 
    tagging_category_code AS id_tagging_category,
    tagging_class, 
    active AS is_active,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM 
    datalake_hogwarts_raw.tag