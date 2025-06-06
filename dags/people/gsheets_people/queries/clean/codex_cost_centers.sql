SELECT
   cc_legacy AS id_cost_center_legacy,
   cc_code AS id_cost_center_current,
   CAST(team_code AS INT) AS team_code,
   cc_full_name AS cost_center_full_name,
   cc_name AS cost_center_name,
   business AS business,
   product AS product,
   brand AS brand,
   team_name AS team,
   structure_name AS structure,
   NULLIF(pt_chapter, '-') AS chapter,
   NULLIF(pt_line, '-') AS line,
   NULLIF(fp_owner, '') AS owner_finance_email,
   NULLIF(l1, '') AS owner_l1_email,
   NULLIF(l2, '') AS owner_l2_email,
   NULLIF(l3, '') AS owner_l3_email,
   status AS cost_center_status,
   CAST(sort AS INT) AS sort_number,
   ts_load
FROM
   datalake_gsheets_people_raw.codex_cost_centers
