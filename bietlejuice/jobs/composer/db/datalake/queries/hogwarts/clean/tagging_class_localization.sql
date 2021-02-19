SELECT
    tagging_class AS id_tagging,
    locale_code AS id_locale,
    `name` AS tagging_name,
    `description` AS tagging_description,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM 
    datalake_hogwarts_raw.tagging_class_localization