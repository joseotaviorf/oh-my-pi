SELECT
  id_contract,
  country_code,
  city,
  guarantee,
  status,
  dt_termination_original,
  dt_annulment,
  dt_started,
  ts_signature,
  ts_analyst_annulment_input,
  ts_database_transaction,
  ts_snapshot,
  year,
  month,
  day,
  NOW() AS ts_load
FROM datalake_collections_aud.contract_aud
WHERE MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, DATE(ts_database_transaction) ORDER BY ts_database_transaction DESC) = 1
