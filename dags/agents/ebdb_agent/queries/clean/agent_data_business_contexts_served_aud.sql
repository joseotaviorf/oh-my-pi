SELECT
    DadosAgente_id AS id_agent_data,
    rev,
    revtype AS rev_type,
    businessContextsServed AS business_context
FROM
    datalake_ebdb_raw.DadosAgente_businessContextsServed_aud