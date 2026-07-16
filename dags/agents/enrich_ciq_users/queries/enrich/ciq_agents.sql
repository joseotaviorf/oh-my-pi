WITH main_demand_data as (
  SELECT
    u.id,
    u.id_agent,
    ag.is_active,
    ag.is_realstate_agent,
    ag.is_photographer,
    ag.is_sale_agent,
    ag.is_rent_agent,
    ag.country_code,
    ag.ts_created,
    ag.ts_updated
  FROM
    datalake_ebdb_user.user AS u
  INNER JOIN 
    datalake_ebdb_user.agent_data AS ag 
      ON ag.id = u.id_agent
)
SELECT 
  cu.id_partner,
  cu.id_user,
  dd.id_agent,
  cu.name,
  cu.email,
  dd.is_active,
  dd.is_realstate_agent,
  dd.is_photographer,
  dd.is_sale_agent,
  dd.is_rent_agent,
  dd.country_code,
  dd.ts_created,
  dd.ts_updated
FROM 
  datalake_ebdb_agents.ciq_users AS cu
INNER JOIN
  main_demand_data AS dd
    ON cu.id_user = dd.id
WHERE
  cu.is_last_status