SELECT
    `id` AS id_agent,
    external_id AS id_external,
    name,
    document_number,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_nazare_raw.agent
