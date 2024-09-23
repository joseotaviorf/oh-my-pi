SELECT
    id,
    REV AS rev,
    state_id AS id_state,
    salesforceId AS id_salesforce,
    gerente_id AS id_manager,
    regiaoPai_id AS id_parent_region,
    REVTYPE AS rev_type,
    nivel AS level,
    nome AS name,
    slug,
    prioridade AS priority,
    lat,
    lng,
    state_MOD AS mod_state
FROM
    datalake_ebdb_raw.Regiao_AUD