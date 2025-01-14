WITH
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
get_agency_name AS (
  SELECT
    COALESCE(c.id_contract_external, SPLIT(hr.id_contract,r'\.')[0]) AS id_contract,
    hr.creditor,
    hr.agency AS agency_group,
    COALESCE(ag.id_agency, hr.agency) AS id_agency,
    COALESCE(agg.agency_name, ag.agency_name) AS agency_name,
    hr.new_debt_amount,
    hr.ts_distribution,
    LAG(COALESCE(agg.agency_name, ag.agency_name)) OVER(PARTITION BY COALESCE(c.id_contract_external, SPLIT(hr.id_contract,r'\.')[0]) ORDER BY hr.ts_distribution) AS previous_agency,
    LEAD(hr.ts_distribution) OVER(PARTITION BY COALESCE(c.id_contract_external, SPLIT(hr.id_contract,r'\.')[0]) ORDER BY hr.ts_distribution) AS ts_redistribution
  FROM datalake_cyber_clean.history_contract_distribution AS hr
  LEFT JOIN datalake_cyber_clean.contracts AS c
    ON hr.id_contract = c.id_contract
  LEFT JOIN datalake_cyber_clean.agency AS ag
    ON hr.agency = ag.id_agency
  LEFT JOIN get_agency_group_name AS agg
    ON ag.id_agency = agg.agency_group
  QUALIFY ROW_NUMBER() OVER(PARTITION BY COALESCE(c.id_contract_external, SPLIT(hr.id_contract,r'\.')[0]), hr.ts_distribution ORDER BY hr.ts_redistribution DESC) = 1
),
capture_changes AS (
  SELECT
    id_contract,
    creditor,
    agency_group,
    id_agency,
    agency_name,
    ts_distribution,
    COALESCE(DATE_SUB(ts_redistribution, 1), CURRENT_DATE) AS ts_redistribution,
    IF(IFNULL(LAG(agency_name) OVER (PARTITION BY creditor, id_contract ORDER BY ts_distribution), "") != agency_name, 1, 0) AS has_changed
  FROM get_agency_name
),
segregate_groups AS (
  SELECT
    id_contract,
    creditor,
    agency_name,
    ts_distribution,
    ts_redistribution,
    SUM(has_changed) OVER (PARTITION BY creditor,id_contract ORDER BY ts_distribution) AS group
  FROM capture_changes
)
SELECT
  id_contract,
  creditor,
  CASE
    WHEN UPPER(agency_name) LIKE "%PASCH%" THEN "PASCHOALOTTO"
    ELSE UPPER(agency_name)
  END AS advisory,
  DATE(MIN(ts_distribution)) AS dt_start_interval,
  DATE(MAX(ts_redistribution)) AS dt_end_interval,
  NOW() AS ts_load
FROM segregate_groups
GROUP BY
  id_contract,
  creditor,
  advisory,
  group
