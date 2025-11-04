SELECT
   cc_code AS cost_center_code,
   business AS business,
   product AS product,
   brand AS brand,
   team_name AS team,
   structure_name AS structure,
   NULLIF(pt_chapter, '-') AS chapter,
   NULLIF(pt_line, '-') AS line,
   NULLIF(l1, '') AS owner_l1_email,
   NULLIF(l2, '') AS owner_l2_email,
   NULLIF(l3, '') AS owner_l3_email,
   dt_updated,
   ts_load,
   MONTH(dt_updated) AS month,
   YEAR(dt_updated) AS year
FROM
   datalake_gsheets_people_raw.codex_cost_centers
