WITH
main_agency_in_group AS (
  SELECT
    id_agency,
    agency_group
  FROM datalake_cyber_clean.agency_group
  QUALIFY ROW_NUMBER() OVER(PARTITION BY agency_group ORDER BY percentage_remuneration DESC) = 1
),
get_agency_name AS (
SELECT
    c.id_contract_external,
    hr.creditor,
    hr.agency AS agency_group,
    COALESCE(ag.id_agency, hr.agency) AS id_agency,
    a.agency_name AS agency_name,
    hr.new_debt_amount,
    hr.ts_distribution,
    hr.ts_redistribution,
    LAG(a.agency_name) OVER(PARTITION BY c.id_contract_external ORDER BY hr.ts_distribution) AS previous_agency
  FROM datalake_cyber_clean.history_contract_distribution AS hr
  INNER JOIN datalake_cyber_clean.contracts AS c
    ON hr.id_contract = c.id_contract
  LEFT JOIN main_agency_in_group AS ag
    ON hr.agency = ag.agency_group
  LEFT JOIN datalake_cyber_clean.agency AS a
    ON COALESCE(ag.id_agency, hr.agency) = a.id_agency
  QUALIFY ROW_NUMBER() OVER(PARTITION BY c.id_contract_external, hr.ts_distribution ORDER BY ts_redistribution DESC) = 1
),
group_changes AS (
  SELECT *,
    SUM(IF(agency_name != previous_agency, 1 , 0)) OVER(PARTITION BY id_contract_external ORDER BY ts_distribution) AS group
  FROM get_agency_name
),
order_changes AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY id_contract_external, group ORDER BY ts_distribution) AS first_row,
    ROW_NUMBER() OVER(PARTITION BY id_contract_external, group ORDER BY ts_distribution DESC) AS last_row
  FROM group_changes
)
SELECT
  id_contract_external,
  creditor,
  agency_name,
  MAX(IF(first_row = 1, DATE(ts_distribution), NULL)) AS dt_start_interval,
  IFNULL(MAX(IF(last_row = 1, DATE_SUB(ts_redistribution,1), NULL)),CURRENT_DATE) AS dt_end_interval,
  NOW() AS ts_load
FROM order_changes
WHERE first_row = 1 OR last_row = 1
GROUP BY
  1,2,3
