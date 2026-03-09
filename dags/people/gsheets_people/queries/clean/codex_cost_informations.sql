SELECT
   cc_code AS cost_center_code,
   pl_line_type AS cost_center_detail,
   CAST(dt_updated AS DATE) AS dt_updated,
   ts_load,
   MONTH(CAST(dt_updated AS DATE)) AS month,
   YEAR(CAST(dt_updated AS DATE)) AS year
FROM
   datalake_gsheets_people_raw.codex_cost_informations