WITH table_usage AS (
  SELECT
    CONCAT(database_name, '.', table_name) AS table_name,
    count_visualization,
    year,
    month,
    day
  FROM
    datalake_trino.table_usage_information
  WHERE 
    MAKE_DATE(year,month,day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
table_dependencies AS (
  SELECT
    dependency_table_name,
    dependent_table_name,
    year,
    month,
    day
  FROM
    datalake_databricks.bietlejuice_table_dependencies_with_indirection
  WHERE 
    MAKE_DATE(year,month,day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
downstream_table_usage AS (
SELECT 
  td.dependency_table_name AS table_name,
  SUM(tu.count_visualization) AS tu.count_visualization,
  td.year,
  td.month,
  td.day
FROM table_dependencies AS td
JOIN 
  table_usage AS tu
    ON td.dependent_table_name = tu.table_name
    AND MAKE_DATE(td.year, td.month, td.day) = MAKE_DATE(tu.year, tu.month, tu.day)
GROUP BY 1,3,4,5
)
SELECT 
  tu.table_name,
  tu.count_visualization as individual_usage,
  COALESCE(dwu.count_visualization, 0) + tu.count_visualization as accumulated_usage,
  tu.year,
  tu.month,
  tu.day
FROM table_usage AS tu
LEFT JOIN 
  downstream_table_usage AS dwu 
    ON dwu.table_name = tu.table_name
      AND MAKE_DATE(dwu.year, dwu.month, dwu.day) = MAKE_DATE(tu.year, tu.month, tu.day)
