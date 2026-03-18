SELECT
    DOCOLLID AS id_document_uploader,
    DOID AS id_document,
    DOACCT AS account,
    DOACCTG AS document_group,
    DODESC AS document_description,
    base64(DOFILE) AS file_blob,
    DONAFILE AS file_name,
    DOSTATUS AS status,
    DOLSTDT AS dt_last_update,
    DOADDDT AS dt_document_added,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.document
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
