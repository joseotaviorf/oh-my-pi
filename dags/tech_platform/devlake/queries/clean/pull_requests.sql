SELECT
    id                                      AS id_pr,
    base_repo_id                            AS id_repo,
    pull_request_key                        AS pr_key,
    title                                   AS pr_title,
    status                                  AS pr_status,
    base_ref                                AS pr_base_branch,
    author_id                               AS id_author_user,
    author_name,
    merged_by_id                            AS id_merged_by_user,
    merged_by_name,
    CASE WHEN status = 'MERGED' THEN TRUE ELSE FALSE END AS is_merged,
    is_draft,
    additions                               AS pr_additions,
    deletions                               AS pr_deletions,
    x_type                                  AS pr_type,
    created_date                            AS ts_created,
    merged_date                             AS ts_merged
FROM
    datalake_devlake_raw.pull_requests
