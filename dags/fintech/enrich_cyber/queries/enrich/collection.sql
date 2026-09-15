WITH codes_descriptions AS (
  SELECT
    code,
    code_type,
    code_description
  FROM (
    SELECT
      UPPER(code) AS code,
      code_type,
      REGEXP_REPLACE(code_description, r'(F\)\s*)', '') AS code_description,
      ROW_NUMBER() OVER(PARTITION BY UPPER(code), code_type ORDER BY `group`) AS rn
    FROM datalake_cyber_clean.logs_code_description
  )
  WHERE rn = 1
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
  FROM (
    SELECT
      action_code,
      result_code,
      complement_code,
      esforco,
      alo,
      cpc,
      promessa,
      ROW_NUMBER() OVER(
        PARTITION BY action_code, result_code, complement_code
        ORDER BY ts_load
      ) AS rn
    FROM datalake_gsheets_clean.cyber_collection_actions
  )
  WHERE rn = 1
),
deduplicate_agency_group AS (
  SELECT
    agency_group,
    id_agency
  FROM (
    SELECT
      agency_group,
      id_agency,
      ROW_NUMBER() OVER(PARTITION BY agency_group ORDER BY percentage_remuneration DESC) AS rn
    FROM datalake_cyber_clean.agency_group
  )
  WHERE rn = 1
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
ranked_logs AS (
  SELECT
    id_contract,
    id_user,
    contract_group,
    creditor,
    region_code,
    action,
    result,
    complement,
    sequence_number,
    comment,
    phone_number,
    phone_extension,
    ts_activity,
    ts_load_cyber,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
      ORDER BY
        sequence_number,
        comment,
        ts_load_cyber,
        action,
        result,
        complement,
        phone_extension,
        region_code
    ) AS log_sequence_rn
  FROM datalake_cyber_clean.logs
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
        LAG(IF(action = '..', NULL, action)) IGNORE NULLS OVER(
          PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
          ORDER BY log_sequence_rn
        )
      ELSE action
    END AS action,
    CASE
      WHEN action = '..' THEN
        LAG(result) IGNORE NULLS OVER(
          PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
          ORDER BY log_sequence_rn
        )
      ELSE result
    END AS result,
    CASE
      WHEN action = '..' THEN
        LAG(complement) IGNORE NULLS OVER(
          PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
          ORDER BY log_sequence_rn
        )
      ELSE complement
    END AS complement,
    sequence_number,
    comment,
    CASE
      WHEN action = '..' THEN
        LAG(phone_number) IGNORE NULLS OVER(
          PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
          ORDER BY log_sequence_rn
        )
      ELSE phone_number
    END AS phone_number,
    CASE
      WHEN action = '..' THEN
        LAG(phone_extension) IGNORE NULLS OVER(
          PARTITION BY id_contract, contract_group, id_user, phone_number, ts_activity
          ORDER BY log_sequence_rn
        )
      ELSE phone_extension
    END AS phone_extension,
    ts_activity,
    ts_load_cyber,
    log_sequence_rn
  FROM ranked_logs
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
    CONCAT_WS(
      '',
      TRANSFORM(
        SORT_ARRAY(COLLECT_LIST(NAMED_STRUCT('rn', log_sequence_rn, 'c', comment))),
        x -> x.c
      )
    ) AS comment
  FROM ordered_logs
  GROUP BY
    id_contract,
    contract_group,
    id_user,
    creditor,
    action,
    result,
    complement,
    phone_number,
    phone_extension,
    ts_activity
)
-- The BROADCAST hints below are required for this query to finish on EMR, not cosmetic.
--
-- Every dimension joined here is small (18 KB - 3 MB), but each is either a Delta table
-- without usable row stats or a CTE wrapped in a window function (`codes_descriptions`,
-- `map_type_occurrence`, `get_agency_group_name`). The planner therefore falls back to
-- `defaultSizeInBytes` and never broadcasts: on cluster j-084138821QBBI4TV9MTO all 12
-- LEFT JOINs planned as SortMergeJoins, each shuffling the ~7 GB `logs` fact table.
--
-- The keys make that fatal. `code_type` plus the action / result / complement codes carry
-- only a few dozen distinct values, so hash partitioning piles nearly everything into a
-- handful of partitions -- 18-46x max/mean task skew across the join chain, with a single
-- 870s task holding up a 190-task stage whose mean task was 19s.
--
-- `datalake_cyber_clean.contracts` (~300 MB) is deliberately NOT broadcast: it joins on
-- the high-cardinality `id_contract` and does not skew.
SELECT /*+ BROADCAST(u, ag, agg, cda, cdaf, cdr, cdrf, cdc, cdcf, lvr, mto) */
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
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%PLC%" THEN "LLC"
    WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name, l.id_user)) LIKE "%LLC%" THEN "LLC"
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
