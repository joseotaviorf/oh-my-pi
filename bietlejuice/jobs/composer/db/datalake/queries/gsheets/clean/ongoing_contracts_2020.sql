SELECT
  CAST(REPLACE(sk_contract, '.', '') AS BIGINT) AS id_contract,
  CAST(REPLACE(sk_user, '.', '') AS BIGINT) AS id_user,
  first_name,
  email,
  cidade AS city,
  estado_abreviacao AS state_abbreviation,
  contract_city,
  DATE(dt_start) AS dt_started
FROM
  datalake_gsheets_raw.ongoing_contracts_2020
