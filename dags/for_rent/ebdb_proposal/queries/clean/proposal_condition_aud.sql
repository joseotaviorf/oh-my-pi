SELECT
    id AS id_proposal_condition,
    REV AS rev,
    rEVTYPE AS rev_type,
    concordado AS has_agreed,
    concordado_MOD AS mod_has_agreed,
    descricao AS description,
    descricao_MOD AS mod_description,
    titulo AS title,
    titulo_MOD as mod_title
FROM
    datalake_ebdb_raw.`condicaoproposta_aud`
