WITH most_recent_id_user AS (
  SELECT
    oh.id_owner,
    oh.id_user
  FROM
    datalake_hubspot.owner_history AS oh
  WHERE
    oh.id_user IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY oh.id_owner, oh.id_user ORDER BY oh.ts_updated DESC) = 1
)
SELECT
  oh.id_owner,
  team.id AS id_current_team,
  COALESCE(oh.id_user, mriu.id_user) AS id_user,
  p.uuid_person,
  team.name AS current_team_name,
  oh.email,
  oh.first_name,
  oh.last_name,
  SPLIT(oh.email, '@')[0] AS owner_user,
  oh.teams,
  oh.is_archived,
  oh.ts_created,
  oh.ts_updated,
  oh.year,
  oh.month,
  oh.day
FROM
  datalake_hubspot.owner_history AS oh
LEFT JOIN
  most_recent_id_user AS mriu
    ON oh.id_owner = mriu.id_owner
LEFT JOIN
  datalake_person_clean.contact_info AS ci
    ON oh.email = ci.contact_info
    AND ci.category = 'EMAIL'
LEFT JOIN
  datalake_person_clean.person AS p
    ON p.id = ci.id_person
LATERAL VIEW
  POSEXPLODE_OUTER(oh.teams) exploded_teams AS position, team
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY oh.id_owner ORDER BY position DESC) = 1