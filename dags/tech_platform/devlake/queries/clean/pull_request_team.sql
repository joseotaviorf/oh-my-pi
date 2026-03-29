SELECT
    base_repo_id        AS id_repo,
    pull_request_key    AS pr_key,
    team_id             AS id_team
FROM
    datalake_devlake_raw.pull_request_team
