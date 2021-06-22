SELECT
    id,
    external_id AS id_external,
    name AS person_name,
    document_number,
    email,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.person