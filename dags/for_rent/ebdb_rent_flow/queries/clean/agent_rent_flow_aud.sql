SELECT
    Agentes_id AS id_agent,
    fluxolocacao_id AS id_rent_flow,
    rev,
    revtype AS rev_type
FROM
    datalake_ebdb_raw.fluxolocacao_dadosagente_aud
