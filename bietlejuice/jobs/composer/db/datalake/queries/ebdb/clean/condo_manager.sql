SELECT
  id,
  state_id AS id_state,
  name AS condo_manager_name,
  email,
  city,
  observation,
  loginSystem AS system_login,
  passwordSystem AS system_password,
  systemUrl AS system_url,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.condomanager
