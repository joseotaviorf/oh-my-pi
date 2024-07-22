WITH enrich_pt AS (
  SELECT
    id_teams,
    email
  FROM
    datalake_product_tech.team_formation_product_tech 
  QUALIFY 
    ROW_NUMBER() OVER (
      PARTITION BY email
      ORDER BY
        ts_change DESC
    ) = 1
)
SELECT
  MD5(
    CONCAT(
      gsheets_pt.email,
      gsheets_pt.subdirectorate,
      COALESCE(gsheets_pt.team_1, '-1'),
      COALESCE(gsheets_pt.team_2, '-1'),
      COALESCE(gsheets_pt.team_3, '-1'),
      COALESCE(gsheets_pt.team_4, '-1'),
      COALESCE(gsheets_pt.team_5, '-1'),
      DATE_FORMAT(gsheets_pt.ts_load, 'yyyyMMdd')
    )
  ) AS id,
  gsheets_pt.id AS id_teams,
  gsheets_pt.email,
  gsheets_pt.employees_name,
  gsheets_pt.subdirectorate,
  gsheets_pt.team_1,
  gsheets_pt.team_2,
  gsheets_pt.team_3,
  gsheets_pt.team_4,
  gsheets_pt.team_5,
  ts_load AS ts_change,
  NOW() AS ts_load
FROM
  datalake_gsheets_clean.team_formation_product_tech AS gsheets_pt
  LEFT JOIN 
    enrich_pt 
      ON gsheets_pt.email = enrich_pt.email
WHERE
  gsheets_pt.id != enrich_pt.id_teams
  OR enrich_pt.id_teams IS NULL