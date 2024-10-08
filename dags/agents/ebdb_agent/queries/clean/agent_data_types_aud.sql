SELECT
    DadosAgente_id as id_agent_data,
    rev,
    revtype AS rev_type,
    tipos as types
FROM 
    datalake_ebdb_raw.dadosagente_tipos_aud