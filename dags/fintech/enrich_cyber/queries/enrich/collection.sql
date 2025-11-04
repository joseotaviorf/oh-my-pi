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
),
ordered_logs AS (
  SELECT
    id_contract,
    id_user,
    contract_group,
    creditor,
    region_code,
    CASE
      WHEN action = '..' THEN
        LAG(IF(action = '..', NULL, action)) IGNORE NULLS OVER(PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity ORDER BY sequence_number)
      ELSE action
    END AS action,
    CASE
      WHEN action = '..' THEN
        LAG(result) IGNORE NULLS OVER(PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity ORDER BY sequence_number)
      ELSE result
    END AS result,
    CASE
      WHEN action = '..' THEN
        LAG(complement) IGNORE NULLS OVER(PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity ORDER BY sequence_number)
      ELSE complement
    END AS complement,
    sequence_number,
    comment,
    CASE
      WHEN action = '..' THEN
        LAG(phone_number) IGNORE NULLS OVER(PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity ORDER BY sequence_number)
      ELSE phone_number
    END AS phone_number,
    CASE
      WHEN action = '..' THEN
        LAG(phone_extension) IGNORE NULLS OVER(PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity ORDER BY sequence_number)
      ELSE phone_extension
    END AS phone_extension,
    ts_activity,
    ts_load_cyber
  FROM datalake_cyber_clean.logs
),
concatenate_comments AS (
  SELECT
    id_contract,
    contract_group,
    id_user,
    creditor,
    action,
    result,
    complement,
    phone_number,
    phone_extension,
    ts_activity,
    CONCAT_WS('', COLLECT_LIST(comment)) AS comment
  FROM ordered_logs
  GROUP BY ALL
)
SELECT
  l.creditor,
  l.id_contract,
  l.contract_group,
  COALESCE(c.id_contract_external, SPLIT(l.id_contract,r'\.')[0]) AS id_contract_external,
  c.id_client AS id_customer,
  UPPER(l.id_user) AS id_operator,
  u.user_email AS operator_email,
  u.user_type AS operator_type,
  COALESCE(agg.agency_name, ag.agency_name) AS agency_name,
  CASE
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "PASCH%" THEN "PASCHOALOTTO"
    WHEN UPPER(l.id_user) LIKE "PSC%" THEN "PASCHOALOTTO"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%TRC%" THEN "TRC"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%GRB%" THEN "BULGARELLI"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%BULGARELLI%" THEN "BULGARELLI"
    WHEN UPPER(l.id_user) LIKE "%BGR%" THEN "BULGARELLI"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%MEETC%" THEN "MEETCALL"
    WHEN UPPER(l.id_user) LIKE "%MTC%" THEN "MEETCALL"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%MONES%" THEN "MONEST"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%PELLON%" THEN "PELLON"
    WHEN UPPER(l.id_user) LIKE "PLL%" THEN "PELLON"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%PLC%" THEN "PLC"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%GONDIM%" THEN "GONDIM"
    WHEN UPPER(l.id_user) LIKE "GAN%" THEN "GONDIM"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%NOVAQ%" THEN "NOVAQUEST"
    WHEN UPPER(l.id_user) LIKE "%NVQ%" THEN "NOVAQUEST"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%PORTAL%" THEN "PORTAL_QUINTOANDAR"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) = "WEBHELP" THEN "WEBHELP"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%WHELP%" THEN "WEBHELP"
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
  l.phone_number,
  l.phone_extension,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    WHEN UPPER(l.result) IN ("UU", "BD") THEN 0
    WHEN UPPER(l.result) IN ("AG", "AE", "AF", "AD", "AB", "AC", "BA", "BC", "XX", "YY") THEN 1
    ELSE COALESCE(mto.esforco, 0)
  END AS esforco,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    WHEN UPPER(l.result) IN ("UU", "BD", "AG", "AD") THEN 0
    WHEN UPPER(l.result) IN ("AE", "AF", "AB", "AC", "BA", "BC", "XX", "YY") THEN 1
    ELSE COALESCE(mto.alo, 0)
  END AS alo,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    WHEN UPPER(l.result) IN ("UU", "AG", "AE", "AD", "AB", "BA", "XX", "BD") THEN 0
    WHEN UPPER(l.result) IN ("AF", "AC", "BC", "YY") THEN 1
    ELSE COALESCE(mto.cpc, 0)
  END AS cpc,
  CASE
    WHEN UPPER(l.id_user) IN ("SISTEMA", "HOST", "RCVRY") THEN 0
    WHEN UPPER(l.complement) IN ("AE") THEN 1
    ELSE COALESCE(mto.promessa, 0)
  END AS promessa,
  l.ts_activity AS ts_occurrence,
  NOW() AS ts_load
FROM concatenate_comments AS l
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON l.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON UPPER(l.id_user) = UPPER(u.id_user)
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON UPPER(COALESCE(u.id_agency, l.id_user)) = ag.id_agency
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
    AND (
      (mto.complement_code IS NULL AND l.complement IS NULL)
        OR mto.complement_code = l.complement
    )
