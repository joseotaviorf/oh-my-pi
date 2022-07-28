SELECT
    tag_code AS id_tag,
    locale_code AS id_locale,
    `name` AS tag_name,
    `description` AS tag_description,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM 
    datalake_hogwarts_raw.tag_localization