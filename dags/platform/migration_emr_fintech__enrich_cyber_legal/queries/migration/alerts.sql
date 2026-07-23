WITH process_info AS (
  SELECT
    p.id_case,
    CASE
      WHEN p.id_contract_cyber RLIKE '^[0-9]+(\\.[0-9]+)*$'
      THEN p.id_contract_cyber
      ELSE NULL
    END AS id_contract_cyber,
    COALESCE(
      c.id_contract_external,
      CASE
        WHEN p.id_contract_cyber RLIKE '^[0-9]+(\\.[0-9]+)*$'
        THEN p.id_contract_cyber
        ELSE NULL
      END
    ) AS id_contract,
    p.process_type,
    p.contract_status,
    p.agency_name
  FROM datalake_cyber_legal.process AS p
  LEFT JOIN datalake_cyber_clean.contracts AS c
    ON p.id_contract_cyber = c.id_contract
), get_last_process_stage AS (
  SELECT
    id_case,
    stage_description
  FROM (
    SELECT
      id_case,
      stage_description,
      ROW_NUMBER() OVER (PARTITION BY id_case ORDER BY stage_order DESC) AS _w,
      stage_order
    FROM datalake_cyber_legal.process_stages
    WHERE
      NOT dt_start IS NULL
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  a.id_alert,
  a.id_case,
  pi.id_contract_cyber,
  pi.id_contract,
  pi.process_type,
  a.alert_type_code,
  vl.value_description AS alert_type_description,
  a.alert_comment,
  pi.agency_name,
  ps.stage_description AS last_process_stage,
  a.id_generating_attorney,
  a.id_revising_attorney,
  pi.contract_status,
  a.alert_creator,
  CASE
    WHEN a.alert_creator IS NULL
    THEN 'SISTEMA'
    WHEN a.alert_creator = 'SISTEMA'
    THEN 'SISTEMA'
    ELSE 'MANUAL'
  END AS alert_type,
  a.is_reviewed,
  CASE
    WHEN CAST(a.dt_alert_expired AS DATE) >= CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)
    THEN 'A vencer'
    WHEN CAST(a.dt_alert_expired AS DATE) < CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)
    THEN 'Vencida'
  END AS task_status,
  DATEDIFF(
    TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
    TO_DATE(CAST(a.dt_alert_expired AS DATE))
  ) AS lead_time,
  CASE
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) = 0
    THEN 'a) Vence hoje'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) BETWEEN -3 AND -1
    THEN 'b) A vencer (1 a 3 dias)'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) BETWEEN -7 AND -4
    THEN 'c) A vencer (4 a 7 dias)'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) < -8
    THEN 'd) A vencer (8+ dias)'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) BETWEEN 1 AND 3
    THEN 'e) Vencida (1 a 3 dias)'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) BETWEEN 4 AND 7
    THEN 'f) Vencida (4 a 7 dias)'
    WHEN DATEDIFF(
      TO_DATE(CAST(COALESCE(a.dt_reviewed, CURRENT_DATE) AS DATE)),
      TO_DATE(CAST(a.dt_alert_expired AS DATE))
    ) > 7
    THEN 'g) Vencida (8+ dias)'
  END AS aging,
  CAST(a.dt_created AS DATE),
  CAST(DATE_TRUNC('MONTH', a.dt_created) AS DATE) AS month_created,
  CAST(a.dt_alert_expired AS DATE) AS dt_alert_expired,
  CAST(a.dt_reviewed AS DATE) AS dt_reviewed
FROM datalake_cyber_legal_clean.case_alert AS a
LEFT JOIN process_info AS pi
  ON a.id_case = pi.id_case
LEFT JOIN datalake_cyber_legal_clean.values_list AS vl
  ON a.alert_type_code = vl.value_code AND vl.id_value = 'L_ALERT'
LEFT JOIN get_last_process_stage AS ps
  ON a.id_case = ps.id_case
