WITH 
issues AS (
  SELECT 
    Address as address,
    REGEXP_REPLACE(LOWER(issue_name), '[\\(\\)\\s]', '') AS normalized_issue_name, 
    CAST(date AS TIMESTAMP) AS dt_report,
    device, 
    YEAR(CAST(date AS TIMESTAMP)) AS year,
    MONTH(CAST(date AS TIMESTAMP)) AS month,
    DAY(CAST(date AS TIMESTAMP)) AS day
  FROM
    datalake_ada_crawls_raw.issues
  WHERE
    date BETWEEN '{load_start_date}' AND '{load_end_date}'

), 
issues_overview_report AS (
  SELECT
    `Issue Name` AS issue_name,
    REGEXP_REPLACE(LOWER(issue_name), '[\\(\\)\\s\\-\\.\\:]', '') AS normalized_issue_name,
    CAST(date AS TIMESTAMP) AS dt_report,
    device
  FROM
    datalake_ada_crawls_raw.issues_overview_report
  WHERE
    date BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
  i.address,
  o.issue_name,
  i.dt_report,
  i.device,
  i.year,
  i.month,
  i.day
FROM 
  issues AS i
LEFT JOIN
  issues_overview_report AS o
ON
  i.normalized_issue_name = o.normalized_issue_name AND i.dt_report = o.dt_report AND i.device = o.device
ORDER BY
  issue_name