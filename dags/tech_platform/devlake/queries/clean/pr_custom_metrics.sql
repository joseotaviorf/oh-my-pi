SELECT
    id                  AS id_pr,
    repo_name,
    pr_released_date    AS ts_released,
    pr_release_time     AS pr_release_time_seconds,
    pr_deploy_time      AS pr_deploy_time_seconds,
    created_at          AS ts_created
FROM
    datalake_devlake_raw.pr_custom_metrics
