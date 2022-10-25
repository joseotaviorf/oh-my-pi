SELECT
    document_code AS id_document,
    tag_code AS id_tag,
    created_on AS ts_created,
    updated_on AS ts_updated
FROM
    datalake_hogwarts_raw.document_x_tag_join