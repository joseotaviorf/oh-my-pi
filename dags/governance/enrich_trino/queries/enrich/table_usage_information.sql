SELECT
  database_name,
  table_name,
  COUNT(DISTINCT id_query) AS count_visualization,
  year,
  month,
  day
FROM
  datalake_trino.query_information
WHERE
  MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
GROUP BY 1, 2, 4, 5, 6