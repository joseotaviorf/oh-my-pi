WITH current_owner AS (
  SELECT
    oh.id_owner,
    oh.id_user,
    oh.email,
    oh.teams,
    oh.is_archived,
    oh.ts_created,
    oh.ts_updated,
    oh.year,
    oh.month,
    oh.day
  FROM
    datalake_hubspot.owner_history AS oh
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY oh.id_owner ORDER BY oh.ts_updated DESC) = 1
)
SELECT
  co.id_owner,
  team.id AS id_current_team,
  co.id_user,
  p.uuid_person,
  team.name AS current_team_name,
  co.email,
  SPLIT(co.email, '@')[0] AS owner_user,
  co.teams,
  co.is_archived,
  co.ts_created,
  co.ts_updated,
  co.year,
  co.month,
  co.day
FROM
  current_owner AS co
LEFT JOIN
  datalake_person_clean.contact_info AS ci
    ON co.email = ci.contact_info
    AND ci.category = 'EMAIL'
LEFT JOIN
  datalake_person_clean.person AS p
    ON p.id = ci.id_person
LATERAL VIEW
  POSEXPLODE_OUTER(co.teams) exploded_teams AS position, team
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY co.id_owner ORDER BY position DESC) = 1