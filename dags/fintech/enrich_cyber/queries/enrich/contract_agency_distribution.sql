WITH
get_last_agency_contract_distribution AS (
  SELECT
    id_contract,
    SPLIT(id_contract,r'\.')[0] AS id_contract_external,
    IF(DATE_DIFF(ts_distribution, ts_redistribution) = 0, new_agency, agency) AS id_agency,
    creditor,
    ts_distribution,
    ts_redistribution
  FROM datalake_cyber_clean.history_contract_distribution
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract_external, ts_distribution ORDER BY ts_redistribution DESC) = 1
),
agency_distribution AS (
  SELECT
    COALESCE(c.id_contract_external, hr.id_contract_external) AS id_contract,
    hr.creditor,
    hr.id_agency,
    hr.ts_distribution,
    LAG(hr.id_agency) OVER(PARTITION BY COALESCE(c.id_contract_external, hr.id_contract_external) ORDER BY hr.ts_distribution) AS previous_agency,
    LEAD(hr.ts_distribution) OVER(PARTITION BY COALESCE(c.id_contract_external, hr.id_contract_external) ORDER BY hr.ts_distribution) AS ts_redistribution
  FROM get_last_agency_contract_distribution AS hr
  LEFT JOIN datalake_cyber_clean.contracts AS c
    ON hr.id_contract = c.id_contract
),
capture_changes AS (
  SELECT
    id_contract,
    creditor,
    id_agency,
    ts_distribution,
    COALESCE(DATE_SUB(ts_redistribution, 1), CURRENT_DATE) AS ts_redistribution,
    IF(IFNULL(LAG(id_agency) OVER (PARTITION BY creditor, id_contract ORDER BY ts_distribution), "") != id_agency, 1, 0) AS has_changed
  FROM agency_distribution
),
segregate_groups AS (
  SELECT
    id_contract,
    creditor,
    id_agency,
    ts_distribution,
    ts_redistribution,
    SUM(has_changed) OVER (PARTITION BY creditor,id_contract ORDER BY ts_distribution) AS group
  FROM capture_changes
),
get_interval AS (
  SELECT
    sg.id_contract,
    sg.creditor,
    sg.id_agency,
    DATE(MIN(sg.ts_distribution)) AS dt_start_interval,
    DATE(MAX(sg.ts_redistribution)) AS dt_end_interval
  FROM segregate_groups AS sg
  GROUP BY
    id_contract,
    creditor,
    id_agency,
    group
)
SELECT
  ge.id_contract,
  ge.creditor,
  ge.id_agency,
  a.id_main_agency,
  a.id_agencies_group,
  a.main_agency_name,
  a.main_agency_type,
  a.agencies_name_group,
  ge.dt_start_interval,
  ge.dt_end_interval,
  NOW() AS ts_load
FROM get_interval AS ge
LEFT JOIN datalake_cyber.agencies AS a
  ON a.id_agency = ge.id_agency
