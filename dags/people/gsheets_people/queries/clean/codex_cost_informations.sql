SELECT
   cc_code AS id_cost_center,
   pl_line_type AS cost_center_detail,
   ts_load
FROM
   datalake_gsheets_people_raw.codex_cost_informations
WHERE
   pl_line_type IS NOT NULL