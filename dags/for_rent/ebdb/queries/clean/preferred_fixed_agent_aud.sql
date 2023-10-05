SELECT
    id,
    rev,
    revtype as rev_type,
    businessContext AS business_context,
    origin,
    isEnabled AS is_enabled,
    businessContext_MOD AS mod_business_context,
    isEnabled_MOD AS mod_is_enabled,
    origin_MOD AS mod_origin,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.preferredfixedagent_aud
