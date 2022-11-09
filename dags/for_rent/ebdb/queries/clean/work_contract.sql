SELECT
  id,
  contractName AS contract_name,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.workcontract
