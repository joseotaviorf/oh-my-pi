SELECT 
    tagging_category_code AS id_tagging_category,
    locale_code AS id_locale,
    `name` AS tagging_category_name,
    `description` AS tagging_category_description,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM
    datalake_hogwarts_raw.tagging_category_localization