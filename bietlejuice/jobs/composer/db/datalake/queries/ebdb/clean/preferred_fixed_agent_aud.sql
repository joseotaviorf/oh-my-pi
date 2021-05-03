SELECT
    id,
    businessContext AS business_context,
    businessContext_MOD AS mod_business_context,
    isEnabled AS is_enabled,
    isEnabled_MOD AS mod_is_enabled,
    rev,
    revtype as rev_type,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.preferredfixedagent_aud