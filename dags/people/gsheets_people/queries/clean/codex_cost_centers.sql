SELECT
   cc_code AS cost_center_code,
   NULLIF(NULLIF(TRIM(business), ''), '-') AS business,
   NULLIF(NULLIF(TRIM(product), ''), '-') AS product,
   NULLIF(NULLIF(TRIM(brand), ''), '-') AS brand,
   NULLIF(NULLIF(TRIM(cc_name), ''), '-') AS team,
   NULLIF(NULLIF(TRIM(structure_name), ''), '-') AS structure,
   NULLIF(NULLIF(TRIM(pt_chapter), ''), '-') AS chapter,
   NULLIF(NULLIF(TRIM(pt_line), ''), '-') AS line,
   NULLIF(NULLIF(TRIM(l1_mail), ''), '-') AS owner_l1_email,
   NULLIF(NULLIF(TRIM(l2_mail), ''), '-') AS owner_l2_email,
   NULLIF(NULLIF(TRIM(l3_mail), ''), '-') AS owner_l3_email,
   CAST(dt_updated AS DATE) AS dt_updated,
   ts_load,
   MONTH(CAST(dt_updated AS DATE)) AS month,
   YEAR(CAST(dt_updated AS DATE)) AS year
FROM
   datalake_gsheets_people_raw.codex_cost_centers