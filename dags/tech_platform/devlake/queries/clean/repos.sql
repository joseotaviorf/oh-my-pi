SELECT
    id          AS id_repo,
    name        AS repo_name,
    url         AS repo_url,
    description AS repo_description,
    language    AS repo_language,
    owner_id    AS id_owner,
    forked_from,
    deleted     AS is_deleted
FROM
    datalake_devlake_raw.repos
