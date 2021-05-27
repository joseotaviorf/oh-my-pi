SELECT
  id_agent AS sk_agent,
  agent_email AS email,
  agent_manager,
  agent_name AS full_name,
  agent_company,
  NOW() AS ts_load
FROM
  datalake_front_tickets.call
GROUP BY 1,2,3,4,5,6
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
GROUP BY 1,2,3,4,5,6
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
GROUP BY 1,2,3,4,5,6