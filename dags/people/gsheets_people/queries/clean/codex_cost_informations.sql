SELECT
   cc_code AS cost_center_code,
   pl_line_type AS cost_center_detail,
   dt_updated,
   ts_load,
   MONTH(dt_updated) AS month,
   YEAR(dt_updated) AS year
FROM
   datalake_gsheets_people_raw.codex_cost_informations