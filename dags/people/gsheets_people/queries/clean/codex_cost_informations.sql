SELECT
   cc_code AS cost_center_code,
   pl_line_type AS cost_center_detail,
   ts_load,
   YEAR(CURRENT_DATE()) AS year,
   MONTH(CURRENT_DATE()) AS month
FROM
   datalake_gsheets_people_raw.codex_cost_informations