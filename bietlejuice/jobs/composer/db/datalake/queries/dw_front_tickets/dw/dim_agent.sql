SELECT
  id_agent AS sk_agent,
  agent_email AS email,
  agent_manager,
  agent_name AS full_name,
  agent_company,
  NOW() AS ts_load
FROM
  datalake_front_tickets.call
UNION ALL
SELECT
  id_agent AS sk_agent,
  agent_email AS email,
  agent_manager,
  agent_name AS full_name,
  agent_company,
  NOW() AS ts_load
FROM
  datalake_front_tickets.chat
UNION ALL
SELECT
  id_agent AS sk_agent,
  agent_email AS email,
  agent_manager,
  agent_name AS full_name,
  agent_company,
  NOW() AS ts_load
FROM
  datalake_front_tickets.email