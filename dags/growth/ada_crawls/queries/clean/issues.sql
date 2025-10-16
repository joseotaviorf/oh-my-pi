SELECT
  Address AS address, 
  issue, 
  device, 
  YEAR(date) AS year,
  MONTH(date) AS month,
  DAY(date) AS day
FROM 
  datalake_ada_crawls_raw.issues
WHERE 
  date BETWEEN '{load_start_date}' AND '{load_end_date}'