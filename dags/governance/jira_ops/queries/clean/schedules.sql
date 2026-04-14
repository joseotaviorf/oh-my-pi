SELECT
    id AS id_schedule,
    teamId AS id_team,
    name,
    description,
    timezone,
    rotations,
    CAST(enabled AS BOOLEAN) AS is_enabled,
    dt_load,
    year,
    month,
    day
FROM
    datalake_jira_ops_raw.schedules
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
