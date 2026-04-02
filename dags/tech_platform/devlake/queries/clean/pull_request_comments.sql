SELECT
    id                      AS id_comment,
    pull_request_id         AS id_pr,
    account_id,
    type,
    status,
    body,
    commit_sha,
    review_id,
    created_date
FROM
    datalake_devlake_raw.pull_request_comments
