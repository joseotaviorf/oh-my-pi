SELECT 
  ct.id_contract,
  ct.status AS termination_status,
  IF(DATE_ADD(ct.dt_termination, 20) > DATE(ct.ts_termination_finished)
    OR (ct.ts_termination_finished IS NULL AND DATE_ADD(ct.dt_termination, 20) > CURRENT_DATE()),
    FALSE, TRUE) AS is_anomaly,
  ct.dt_termination,
  DATE(ct.ts_termination_finished) AS dt_termination_finished,
  DATE_ADD(ct.dt_termination, 20) AS dt_termination_expected_finish
FROM
  datalake_offboarding.contract_termination AS ct
JOIN
  datalake_ebdb_contract.contract AS c
    ON c.country_code = 'BR'
    AND ct.id_contract = c.id
WHERE
  ct.status <> 'CANCELED'
  AND DATE_ADD(ct.dt_termination, 20) < CURRENT_DATE()