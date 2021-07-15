SELECT
  cpf,
  cnpj,
  creci,
  full_name,
  quintoandar_email,
  personal_number,
  status,
  register_status,
  function_type,
  hub_region,
  manager,
  CAST(has_email_quintoandar AS BOOLEAN) AS has_email_quintoandar,
  CAST(dt_entrance AS DATE) AS dt_entrance,
  CAST(dt_ended AS DATE) AS dt_ended
FROM
  datalake_gsheets_raw.hub_agents_hierarchy
