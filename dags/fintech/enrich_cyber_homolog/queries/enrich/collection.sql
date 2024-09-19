SELECT
  c.id_contract,
  c.id_contract_external,
  c.id_client AS id_customer,
  UPPER(l.id_user) AS id_operator,
  l.contract_group AS creditor,
  u.user_email AS operator_email,
  u.user_type AS operator_type,
  ag.agency_name AS operator_agency,
  l.action,
  cda.code_description AS action_description,
  l.result,
  cdr.code_description AS result_description,
  l.complement AS complement,
  cdc.code_description AS complement_description,
  l.comment AS occurrence_description,
  l.ts_activity AS ts_occurrence,
  cca.esforco,
  cca.alo,
  cca.cpc,
  cca.acordo,
  NOW() AS ts_load
FROM datalake_cyber_clean.logs AS l
INNER JOIN datalake_cyber_clean.contracts AS c
  ON l.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON UPPER(l.id_user) = UPPER(u.id_user)
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
LEFT JOIN datalake_cyber_clean.logs_code_description AS cda
  ON l.action = cda.code AND cda.code_type == "Ação"
LEFT JOIN datalake_cyber_clean.logs_code_description AS cdr
  ON l.result = cdr.code AND cdr.code_type == "Resultado"
LEFT JOIN datalake_cyber_clean.logs_code_description AS cdc
  ON l.complement = cdc.code AND cdc.code_type == "Carta"
LEFT JOIN datalake_gsheets_clean.cyber_collection_actions AS cca
  ON cca.action_code = l.action
    AND cca.result_code = l.result
    AND cca.complement_code = l.complement
WHERE UPPER(l.id_user) NOT IN ("SISTEMA", "HOST", "RCVRY")
