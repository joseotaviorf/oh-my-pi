SELECT 
  `Issue Name` AS issue_name,
  `Issue Type` AS issue_type,
  `Issue Priority` AS issue_priority,
  `Description` AS description,
  `How To Fix` AS how_to_fix,
  `Help URL` AS help_url,
  URLs AS url_count,
  `% of Total` AS percentage_of_total,
  date AS dt_report,
  device,
  YEAR(date) AS year,
  MONTH(date) AS month,
  DAY(date) AS day
FROM 
  datalake_ada_crawls_raw.issues_overview_report
WHERE 
  date BETWEEN '{load_start_date}' AND '{load_end_date}'