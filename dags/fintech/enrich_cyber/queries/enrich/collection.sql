WITH codes_descriptions AS (
  SELECT DISTINCT
    UPPER(code) AS code,
    code_type,
    REGEXP_REPLACE(code_description, r'(F\)\s*)','') AS code_description
  FROM datalake_cyber_clean.logs_code_description
  QUALIFY ROW_NUMBER() OVER(PARTITION BY code,code_type ORDER BY group) = 1
),
map_type_occurrence AS (
  SELECT
    action_code,
    result_code,
    complement_code,
    esforco,
    alo,
    cpc,
    promessa
  FROM datalake_gsheets_clean.cyber_collection_actions
  QUALIFY ROW_NUMBER() OVER(PARTITION BY action_code, result_code, complement_code ORDER BY ts_load) = 1
),
deduplicate_agency_group AS (
  SELECT
    agency_group,
    id_agency
  FROM datalake_cyber_clean.agency_group
  QUALIFY ROW_NUMBER() OVER(PARTITION BY agency_group ORDER BY percentage_remuneration DESC) = 1
),
get_agency_group_name AS (
  SELECT
    ag.agency_group,
    a.id_agency,
    a.agency_name
  FROM deduplicate_agency_group AS ag
  LEFT JOIN datalake_cyber_clean.agency AS a
    ON ag.id_agency = a.id_agency
)
SELECT
  l.creditor,
  l.id_contract,
  COALESCE(c.id_contract_external, SPLIT(l.id_contract,r'\.')[0]) AS id_contract_external,
  c.id_client AS id_customer,
  UPPER(l.id_user) AS id_operator,
  u.user_email AS operator_email,
  u.user_type AS operator_type,
  CASE
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name)) LIKE "PASCH%" THEN "PASCHOALOTTO"
    WHEN UPPER(l.id_user) LIKE "PSC%" THEN "PASCHOALOTTO"
    ELSE UPPER(COALESCE(agg.agency_name, ag.agency_name))
  END AS operator_agency,
  UPPER(l.action) AS action,
  COALESCE(cda.code_type, cdaf.code_type) AS action_code_type,
  COALESCE(cda.code_description, cdaf.code_description) AS action_description,
  UPPER(l.result) AS result,
  COALESCE(cdr.code_type, cdrf.code_type) AS result_code_type,
  COALESCE(cdr.code_description, cdrf.code_description) AS result_description,
  UPPER(l.complement) AS complement,
  COALESCE(cdc.code_type, cdcf.code_type) AS complement_code_type,
  COALESCE(cdc.code_description, cdcf.code_description) AS complement_description,
  l.comment AS occurrence_description,
  lvr.comment_pre_defined AS action_result_pre_defined_comment,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    ELSE mto.esforco
  END AS esforco,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    ELSE mto.alo
  END AS alo,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    ELSE mto.cpc
  END AS cpc,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    ELSE mto.promessa
  END AS promessa,
  l.ts_activity AS ts_occurrence,
  NOW() AS ts_load
FROM datalake_cyber_clean.logs AS l
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON l.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON UPPER(l.id_user) = UPPER(u.id_user)
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
LEFT JOIN get_agency_group_name AS agg
  ON ag.id_agency = agg.agency_group
LEFT JOIN codes_descriptions AS cda
    ON UPPER(l.action) = cda.code AND cda.code_type = 'Ação'
LEFT JOIN codes_descriptions AS cdaf
    ON UPPER(l.action) = cdaf.code AND cdaf.code_type = 'Função'
LEFT JOIN codes_descriptions AS cdr
    ON UPPER(l.result) = cdr.code AND cdr.code_type = 'Resultado'
LEFT JOIN codes_descriptions AS cdrf
    ON UPPER(l.result) = cdrf.code AND cdrf.code_type ='Função'
LEFT JOIN codes_descriptions AS cdc
    ON UPPER(l.complement) = cdc.code AND cdc.code_type = 'Carta'
LEFT JOIN codes_descriptions AS cdcf
    ON UPPER(l.complement) = cdcf.code AND cdcf.code_type = 'Função'
LEFT JOIN datalake_cyber_clean.logs_valid_result_code AS lvr
  ON UPPER(l.action) = UPPER(lvr.id_action) AND UPPER(l.result) = UPPER(lvr.id_result)
LEFT JOIN map_type_occurrence AS mto
  ON mto.action_code = l.action
    AND mto.result_code = l.result
    AND mto.complement_code = l.complement
QUALIFY ROW_NUMBER() OVER(PARTITION BY l.id_contract, UPPER(l.id_user), l.action, l.result, l.complement, l.comment, l.ts_activity ORDER BY l.ts_activity) = 1
