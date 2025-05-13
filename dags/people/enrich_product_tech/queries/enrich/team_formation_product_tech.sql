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
SELECT DISTINCT
  MD5(
    CONCAT(
      gsheets_pt.id,
      DATE_FORMAT(gsheets_pt.ts_load, 'yyyyMMdd')
    )
  ) AS id,
  gsheets_pt.id AS id_teams,
  gsheets_pt.assignment_number,
  gsheets_pt.email,
  gsheets_pt.employee_name,
  gsheets_pt.line,
  gsheets_pt.chapter,
  gsheets_pt.team_1,
  gsheets_pt.team_2,
  gsheets_pt.team_3,
  gsheets_pt.team_4,
  gsheets_pt.team_5,
  gsheets_pt.team_6,
  gsheets_pt.team_7,
  gsheets_pt.team_8,
  gsheets_pt.team_9,
  gsheets_pt.team_10,
  gsheets_pt.line_leader,
  gsheets_pt.team_leader,
  is_line_leader,
  is_team_leader,
  ts_load AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_gsheets_people_clean.team_formation_product_tech AS gsheets_pt
LEFT JOIN 
  enrich_pt 
    ON gsheets_pt.email = enrich_pt.email
WHERE
  gsheets_pt.id != enrich_pt.id_teams
  OR enrich_pt.id_teams IS NULL