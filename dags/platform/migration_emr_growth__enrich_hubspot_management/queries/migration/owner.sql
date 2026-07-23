WITH current_owner AS (
  SELECT
    id_owner,
    id_user,
    email,
    first_name,
    last_name,
    teams,
    is_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
  FROM (
    SELECT
      oh.id_owner,
      oh.id_user,
      oh.email,
      oh.first_name,
      oh.last_name,
      oh.teams,
      oh.is_archived,
      oh.ts_created,
      oh.ts_updated,
      oh.year,
      oh.month,
      oh.day,
      ROW_NUMBER() OVER (PARTITION BY oh.id_owner ORDER BY oh.ts_updated DESC) AS _w
    FROM datalake_hubspot.owner_history AS oh
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_owner,
  id_current_team,
  id_user,
  uuid_person,
  current_team_name,
  email,
  first_name,
  last_name,
  owner_user,
  teams,
  is_archived,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT
    co.id_owner,
    team.id AS id_current_team,
    co.id_user,
    p.uuid_person,
    team.name AS current_team_name,
    co.email,
    co.first_name,
    co.last_name,
    SPLIT(co.email, '@')[0] AS owner_user,
    co.teams,
    co.is_archived,
    co.ts_created,
    co.ts_updated,
    co.year,
    co.month,
    co.day,
    ROW_NUMBER() OVER (PARTITION BY co.id_owner ORDER BY position DESC) AS _w,
    position
  FROM current_owner AS co
  LEFT JOIN datalake_person_clean.contact_info AS ci
    ON co.email = ci.contact_info AND ci.category = 'EMAIL'
  LEFT JOIN datalake_person_clean.person AS p
    ON p.id = ci.id_person
  LATERAL VIEW
  POSEXPLODE_OUTER(co.teams) exploded_teams AS position, team
) AS _t
WHERE
  _w = 1