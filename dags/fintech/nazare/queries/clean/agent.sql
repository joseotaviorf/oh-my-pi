SELECT
    BIGINT(`id`) AS id_agent,
    BIGINT(external_id) AS id_external,
    name,
    email,
    document_number,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_nazare_raw.agent
