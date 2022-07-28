SELECT
    id,
    agentData_id AS id_agent_data,
    region_id AS id_region,
    userVisitPreferences_id AS id_user_visit_preferences,
    businessContext AS business_context,
    isEnabled AS is_enabled,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.preferredfixedagent