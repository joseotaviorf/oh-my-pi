SELECT
    id          AS id_team,
    name        AS team_name,
    alias       AS team_alias,
    type        AS team_type,
    parent_id   AS id_parent_team
FROM
    datalake_devlake_raw.teams
