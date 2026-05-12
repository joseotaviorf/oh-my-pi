SELECT
  COALESCE(a3p.id_agent, 0, a3p.version) AS sk_agent_3p_history,
  a3p.id_agent AS sk_agent,
  COALESCE(a3p.id_user, -1) AS sk_user,
  COALESCE(cb.sk_broker, -1) AS sk_broker,
  a3p.agent_type,
  a3p.contract_name,
  a3p.version,
  a3p.is_3p_agent,
  a3p.is_active,
  a3p.is_passive_lead_receiver,
  a3p.is_current,
  a3p.is_deleted,
  a3p.ts_started,
  a3p.ts_ended,
  CURRENT_TIMESTAMP AS ts_load
FROM
  datalake_ebdb_agents.agent_3p_history AS a3p
LEFT JOIN
  core_brokers.brokers AS cb
    ON a3p.uuid_company = cb.uuid_company