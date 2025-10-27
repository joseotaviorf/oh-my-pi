SELECT
   cc_code AS cost_center_code,
   pl_line_type AS cost_center_detail,
   ts_load,
   YEAR(ts_load) AS year,
   MONTH(ts_load) AS month
FROM
   datalake_gsheets_people_raw.codex_cost_informations