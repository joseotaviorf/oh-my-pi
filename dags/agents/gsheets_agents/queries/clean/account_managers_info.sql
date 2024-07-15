SELECT
  CAST(id AS LONG) AS id_user,
  nome AS account_manager_name,
  time AS account_manager_team,
  funcao AS account_manager_function,
  status AS account_manager_status,
  obs AS additional_information 
FROM
  datalake_gsheets_raw.account_managers_info