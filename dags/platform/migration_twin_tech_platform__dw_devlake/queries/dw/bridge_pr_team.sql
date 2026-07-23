SELECT
    SHA2(pr.id_pr, 256)     AS sk_pr,
    SHA2(prt.id_team, 256)  AS sk_team,
    pr.id_pr,
    prt.id_repo,
    prt.pr_key,
    prt.id_team,
    CURRENT_TIMESTAMP()     AS ts_load
FROM
    datalake_devlake_clean.pull_request_team AS prt
JOIN
    datalake_devlake_clean.pull_requests AS pr
    ON prt.id_repo = pr.id_repo
    AND prt.pr_key = pr.pr_key
