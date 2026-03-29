WITH primary_team AS (
    SELECT
        id_repo,
        pr_key,
        MIN(id_team) AS id_team
    FROM
        datalake_devlake_clean.pull_request_team
    GROUP BY
        id_repo,
        pr_key
)
SELECT
    SHA2(pr.id_pr, 256)             AS sk_pr,
    SHA2(pr.id_repo, 256)           AS sk_repo,
    SHA2(pr.id_author_user, 256)    AS sk_author_user,
    SHA2(pr.id_merged_by_user, 256) AS sk_merged_by_user,
    SHA2(pt.id_team, 256)           AS sk_team,
    CAST(
        DATE_FORMAT(CAST(pr.ts_created AS DATE), 'yyyyMMdd') AS INT
    )                               AS sk_created_date,
    CAST(
        DATE_FORMAT(CAST(pr.ts_merged AS DATE), 'yyyyMMdd') AS INT
    )                               AS sk_merged_date,
    CAST(
        DATE_FORMAT(CAST(pcm.ts_released AS DATE), 'yyyyMMdd') AS INT
    )                               AS sk_released_date,
    pr.id_pr,
    pr.id_repo,
    pr.pr_key,
    pr.pr_title,
    pr.pr_status,
    pr.pr_base_branch,
    pr.pr_type,
    pr.is_merged,
    pr.is_draft,
    pr.pr_additions,
    pr.pr_deletions,
    pcm.pr_release_time_seconds,
    pcm.pr_deploy_time_seconds,
    CAST(pr.ts_created AS DATE)     AS dt_created,
    CAST(pr.ts_merged AS DATE)      AS dt_merged,
    CAST(pcm.ts_released AS DATE)   AS dt_released,
    CURRENT_TIMESTAMP()             AS ts_load
FROM
    datalake_devlake_clean.pull_requests AS pr
LEFT JOIN
    datalake_devlake_clean.pr_custom_metrics AS pcm
    ON pr.id_pr = pcm.id_pr
LEFT JOIN
    primary_team AS pt
    ON pr.id_repo = pt.id_repo
    AND pr.pr_key = pt.pr_key
