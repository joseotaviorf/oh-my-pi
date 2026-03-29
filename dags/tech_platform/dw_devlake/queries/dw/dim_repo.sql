SELECT
    SHA2(id_repo, 256)  AS sk_repo,
    id_repo,
    repo_name,
    repo_url,
    repo_description,
    repo_language,
    id_owner,
    forked_from,
    is_deleted,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_devlake_clean.repos
