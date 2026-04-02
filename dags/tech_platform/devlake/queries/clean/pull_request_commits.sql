SELECT
    commit_sha,
    pull_request_id         AS id_pr,
    commit_author_name,
    commit_author_email,
    commit_authored_date
FROM
    datalake_devlake_raw.pull_request_commits
