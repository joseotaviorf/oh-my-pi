SELECT 
    document_code AS id_document,
    locale_code AS id_locale,
    title,
    `text` AS document_content,
    link,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM
    datalake_hogwarts_raw.document_localization