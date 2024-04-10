WITH agents AS(
  SELECT
    MAX(a.id_agent) AS sk_agent,
    MAX(a.id_agent_twilio) AS sk_agent_twilio,
    MAX(a.name) AS full_name,
    a.email,
    MAX(a.phone) AS phone,
    MAX(a.organization) AS agent_organization,
    MAX(a.organization) AS agent_company,
    MAX(ac.manager) AS agent_manager,
    MAX(DATE(a.ts_created)) AS dt_agent_start
  FROM
    datalake_support_users.analysts AS a
  LEFT JOIN
    datalake_gsheets_clean.agents_control AS ac
      ON a.email = LOWER(ac.email)
  GROUP BY
    a.email
)
SELECT
  MD5(email) AS sk_agent,
  sk_agent_twilio,
  full_name,
  email,
  phone,
  agent_organization,
  agent_company,
  agent_manager,
  dt_agent_start,
  NOW() AS ts_load
FROM
  agents
