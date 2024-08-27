SELECT
    DOID AS id_document,
    DOACCT AS id_contract,
    CASE
        WHEN DOACCTG = "1" THEN "QuintoAndar"
        WHEN DOACCTG = "2" THEN "QuintoCred"
        ELSE DOACCTG
    END AS contract_group,
    DOCOLLID AS manager_attached_document,
    DODESC AS document_description,
    DOFILE AS attached_document,
    DONAFILE AS file,
    DOSTATUS AS status,
    DOADDDT AS ts_update,
    DOLSTDT AS ts_last,
    NOW() AS ts_load
FROM datalake_cyber_raw.document
