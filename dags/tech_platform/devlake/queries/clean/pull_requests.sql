WITH user_lookup AS (
    SELECT
        lower(github_user) AS github_username,
        MIN(id)            AS id_user
    FROM
        datalake_devlake_raw.users
    WHERE
        github_user IS NOT NULL
        AND github_user <> ''
    GROUP BY
        lower(github_user)
)

SELECT
    pr.id                                      AS id_pr,
    pr.base_repo_id                            AS id_repo,
    pr.pull_request_key                        AS pr_key,
    pr.title                                   AS pr_title,
    pr.status                                  AS pr_status,
    pr.base_ref                                AS pr_base_branch,
    ul_author.id_user                          AS id_author_user,
    pr.author_name,
    ul_merger.id_user                          AS id_merged_by_user,
    pr.merged_by_name,
    CASE WHEN pr.status = 'MERGED' THEN TRUE ELSE FALSE END AS is_merged,
    pr.is_draft,
    pr.additions                               AS pr_additions,
    pr.deletions                               AS pr_deletions,
    pr.x_type                                  AS pr_type,
    pr.created_date                            AS ts_created,
    pr.merged_date                             AS ts_merged
FROM
    datalake_devlake_raw.pull_requests AS pr
LEFT JOIN
    user_lookup AS ul_author
    ON lower(pr.author_name) = ul_author.github_username
LEFT JOIN
    user_lookup AS ul_merger
    ON lower(pr.merged_by_name) = ul_merger.github_username
