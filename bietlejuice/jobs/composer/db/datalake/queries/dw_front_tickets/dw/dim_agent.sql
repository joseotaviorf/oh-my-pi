WITH agents AS (
  SELECT
    id_agent AS sk_agent,
    agent_email AS email,
    agent_manager,
    agent_name AS full_name,
    LOWER(agent_company) AS agent_company
  FROM
    datalake_front_tickets.call
  UNION ALL
  SELECT
    id_agent AS sk_agent,
    agent_email AS email,
    agent_manager,
    agent_name AS full_name,
    LOWER(agent_company) AS agent_company
  FROM
    datalake_front_tickets.chat
  UNION ALL
  SELECT
    id_agent AS sk_agent,
    agent_email AS email,
    agent_manager,
    agent_name AS full_name,
    LOWER(agent_company) AS agent_company
  FROM
    datalake_front_tickets.email
)
SELECT
  sk_agent,
  FIRST(email, TRUE) AS email,
  FIRST(agent_manager, TRUE) AS agent_manager,
  FIRST(full_name, TRUE) AS full_name,
  FIRST(agent_company, TRUE) AS agent_company,
  NOW() AS ts_load
FROM
  agents
GROUP BY 1