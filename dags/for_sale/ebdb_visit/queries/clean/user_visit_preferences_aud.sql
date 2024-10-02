SELECT
    id,
    preferredFixedAgentEnabled AS is_preferred_fixed_agent_enabled,
    preferredFixedAgentEnabled_MOD AS mod_is_preferred_fixed_agent_enabled,
    rev,
    revtype AS rev_type,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_test_raw.uservisitpreferences_aud
