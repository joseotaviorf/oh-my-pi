SELECT
    id,
    user_id AS id_user,
    preferredFixedAgentEnabled AS is_preferred_fixed_agent_enabled,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_test_raw.uservisitpreferences
