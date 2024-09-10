SELECT
  c.id_contract_external AS id_contract,
  c.id_client AS id_customer,
  UPPER(l.id_user) AS id_operator,
  l.contract_group AS creditor,
  u.user_type AS company,
  l.action,
  a.code_description AS action_description,
  l.result,
  aa.code_description AS result_description,
  l.complement AS complement,
  aa.code_description AS complement_description,
  l.comment AS occurrence_description,
  NULL AS esforco,
  NULL AS alo,
  NULL AS cpc,
  NULL AS promisse,
  NULL AS agreement,
  NULL AS failure,
  l.ts_activity AS ts_occurrence
FROM datalake_cyber_clean.logs AS l
INNER JOIN datalake_cyber_clean.contracts AS c
LEFT JOIN datalake_cyber_clean.users AS u
  ON l.id_user = u.id_user
LEFT JOIN datalake_cyber_clean.logs_code_description AS a
  ON l.action = a.code AND a.code_type == "Ação"
LEFT JOIN datalake_cyber_clean.logs_code_description AS aa
  ON l.result = aa.code AND aa.code_type == "Resultado"
LEFT JOIN datalake_cyber_clean.logs_code_description AS aaa
  ON l.complement = aaa.code AND aaa.code_type == "Carta"
