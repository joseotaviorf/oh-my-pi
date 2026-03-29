SELECT
    SHA2(t.id_team, 256)    AS sk_team,
    t.id_team,
    t.team_name,
    t.team_alias,
    t.team_type,
    t.id_parent_team,
    l.team_name             AS line_name,
    l.team_alias            AS line_alias,
    CURRENT_TIMESTAMP()     AS ts_load
FROM
    datalake_devlake_clean.teams AS t
LEFT JOIN
    datalake_devlake_clean.teams AS l
    ON t.id_parent_team = l.id_team
