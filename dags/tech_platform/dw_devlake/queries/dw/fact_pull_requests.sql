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
),

commit_stats AS (
    SELECT
        id_pr,
        COUNT(*)                       AS commit_count,
        MIN(commit_authored_date)      AS first_commit_ts,
        MAX(commit_authored_date)      AS last_commit_ts
    FROM
        datalake_devlake_clean.pull_request_commits
    GROUP BY
        id_pr
),

bot_accounts (account_id) AS (
    VALUES
        ('github:GithubAccount:4:113528307'),   -- quintoandar-atlantis-v2[bot]
        ('github:GithubAccount:4:141718529'),   -- snyk-io[bot]
        ('github:GithubAccount:4:152914687'),   -- sonarqube-9-scan[bot]
        ('github:GithubAccount:4:148880201'),   -- code-scanner (NORMAL+DIFF, 0 approvals)
        ('github:GithubAccount:4:66275788'),    -- chip-n-dale[bot]
        ('github:GithubAccount:4:54044254'),    -- homesbot (auto-approver)
        ('github:GithubAccount:4:114699916'),   -- homesbot-jr (auto-approver)
        ('github:GithubAccount:4:41898282'),    -- github-actions[bot]
        ('github:GithubAccount:4:89148315'),    -- quintoandar-atlantis-dev[bot]
        ('github:GithubAccount:4:254448843'),   -- unknown bot (NORMAL only)
        ('github:GithubAccount:4:49699333'),    -- dependabot[bot]
        ('github:GithubAccount:4:104796951'),   -- backstage-foreman[bot]
        ('github:GithubAccount:4:119428613'),   -- comms-manager[bot]
        ('github:GithubAccount:4:129190226'),   -- rocko-deployer[bot]
        ('github:GithubAccount:4:159380293'),   -- sonarqube-community-in-forno[bot]
        ('github:GithubAccount:4:39514782'),    -- sonarcloud[bot]
        ('github:GithubAccount:4:39604003'),    -- sentry-io[bot]
        ('github:GithubAccount:4:0'),           -- system/ghost account
        ('github:GithubAccount:5:0')            -- system/ghost account (conn 5)
),

comment_stats AS (
    SELECT
        c.id_pr,
        COUNT(*)                                                                          AS comment_count,
        SUM(CASE WHEN c.type = 'REVIEW'                            THEN 1 ELSE 0 END)    AS review_comment_count,
        SUM(CASE WHEN c.type = 'DIFF'                              THEN 1 ELSE 0 END)    AS diff_comment_count,
        SUM(CASE WHEN c.type = 'REVIEW' AND c.status = 'APPROVED'             THEN 1 ELSE 0 END)    AS approval_count,
        SUM(CASE WHEN c.type = 'REVIEW' AND c.status = 'CHANGES_REQUESTED'    THEN 1 ELSE 0 END)    AS changes_requested_count,
        SUM(CASE WHEN c.type = 'REVIEW' AND c.status = 'DISMISSED'              THEN 1 ELSE 0 END)    AS dismissed_review_count,
        COUNT(DISTINCT CASE WHEN c.type IN ('REVIEW', 'DIFF')         THEN c.account_id END) AS reviewer_count,
        MIN(c.created_date)                                                               AS first_comment_ts,
        MIN(CASE WHEN c.type = 'REVIEW' AND c.status = 'APPROVED'
                 THEN c.created_date END)                                                 AS first_approval_ts,

        SUM(CASE WHEN b.account_id IS NOT NULL                     THEN 1 ELSE 0 END)    AS bot_comment_count,
        SUM(CASE WHEN b.account_id IS NULL                         THEN 1 ELSE 0 END)    AS human_comment_count,
        SUM(CASE WHEN b.account_id IS NULL AND c.type = 'REVIEW' AND c.status = 'APPROVED'
                 THEN 1 ELSE 0 END)                                                       AS human_approval_count,
        COUNT(DISTINCT CASE WHEN b.account_id IS NULL AND c.type IN ('REVIEW', 'DIFF')
                            THEN c.account_id END)                                        AS human_reviewer_count,
        MIN(CASE WHEN b.account_id IS NULL
                 THEN c.created_date END)                                                 AS first_human_comment_ts,
        MIN(CASE WHEN b.account_id IS NULL AND c.type = 'REVIEW' AND c.status = 'APPROVED'
                 THEN c.created_date END)                                                 AS first_human_approval_ts,

        SUM(CASE WHEN b.account_id IS NULL AND c.type = 'DIFF'
                 THEN 1 ELSE 0 END)                                                       AS human_diff_comment_count,
        SUM(CASE WHEN b.account_id IS NULL AND c.type = 'DIFF'
                      AND c.body LIKE '%```suggestion%'
                 THEN 1 ELSE 0 END)                                                       AS suggestion_count,
        SUM(CASE WHEN b.account_id IS NULL AND c.type = 'DIFF'
                      AND (c.body LIKE '%```suggestion%'
                           OR c.body LIKE '%nit:%' OR c.body LIKE '%Nit:%' OR c.body LIKE '%NIT:%'
                           OR c.body LIKE '%should%' OR c.body LIKE '%could%'
                           OR c.body LIKE '%consider%' OR c.body LIKE '%instead%'
                           OR c.body LIKE '%better%' OR c.body LIKE '%prefer%'
                           OR c.body LIKE '%bug%' OR c.body LIKE '%wrong%'
                           OR c.body LIKE '%error%' OR c.body LIKE '%fix%'
                           OR c.body LIKE '%TODO%' OR c.body LIKE '%FIXME%')
                 THEN 1 ELSE 0 END)                                                       AS actionable_comment_count,
        SUM(CASE WHEN b.account_id IS NULL AND c.type = 'DIFF'
                      AND c.body LIKE '%?%' AND LENGTH(c.body) < 200
                      AND c.body NOT LIKE '%```suggestion%'
                 THEN 1 ELSE 0 END)                                                       AS question_comment_count
    FROM
        datalake_devlake_clean.pull_request_comments AS c
    LEFT JOIN
        bot_accounts AS b ON c.account_id = b.account_id
    GROUP BY
        c.id_pr
)

SELECT
    SHA2(pr.id_pr, 256)             AS sk_pr,
    SHA2(pr.id_repo, 256)           AS sk_repo,
    COALESCE(SHA2(pr.id_author_user, 256), '-1')    AS sk_author_user,
    COALESCE(SHA2(pr.id_merged_by_user, 256), '-1') AS sk_merged_by_user,
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
    CAST(
        DATE_FORMAT(CAST(cs.first_commit_ts AS DATE), 'yyyyMMdd') AS INT
    )                               AS sk_first_commit_date,
    CAST(
        DATE_FORMAT(CAST(cms.first_approval_ts AS DATE), 'yyyyMMdd') AS INT
    )                               AS sk_first_approval_date,

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

    COALESCE(cs.commit_count, 0)                AS commit_count,
    COALESCE(cms.comment_count, 0)              AS comment_count,
    COALESCE(cms.review_comment_count, 0)       AS review_comment_count,
    COALESCE(cms.diff_comment_count, 0)         AS diff_comment_count,
    COALESCE(cms.approval_count, 0)             AS approval_count,
    COALESCE(cms.changes_requested_count, 0)    AS changes_requested_count,
    COALESCE(cms.dismissed_review_count, 0)     AS dismissed_review_count,
    COALESCE(cms.reviewer_count, 0)             AS reviewer_count,

    COALESCE(cms.bot_comment_count, 0)          AS bot_comment_count,
    COALESCE(cms.human_comment_count, 0)        AS human_comment_count,
    COALESCE(cms.human_approval_count, 0)       AS human_approval_count,
    COALESCE(cms.human_reviewer_count, 0)       AS human_reviewer_count,
    COALESCE(cms.human_diff_comment_count, 0)   AS human_diff_comment_count,
    COALESCE(cms.suggestion_count, 0)           AS suggestion_count,
    COALESCE(cms.actionable_comment_count, 0)   AS actionable_comment_count,
    COALESCE(cms.question_comment_count, 0)     AS question_comment_count,

    CASE
        WHEN pr.pr_additions + pr.pr_deletions <= 10  THEN 'XS'
        WHEN pr.pr_additions + pr.pr_deletions <= 50  THEN 'S'
        WHEN pr.pr_additions + pr.pr_deletions <= 200 THEN 'M'
        WHEN pr.pr_additions + pr.pr_deletions <= 500 THEN 'L'
        ELSE 'XL'
    END                                         AS pr_size_category,

    BIGINT(
        UNIX_TIMESTAMP(pr.ts_created) - UNIX_TIMESTAMP(cs.first_commit_ts)
    )                                           AS coding_time_seconds,
    BIGINT(
        UNIX_TIMESTAMP(cms.first_comment_ts) - UNIX_TIMESTAMP(pr.ts_created)
    )                                           AS review_wait_seconds,
    BIGINT(
        UNIX_TIMESTAMP(cms.first_approval_ts) - UNIX_TIMESTAMP(pr.ts_created)
    )                                           AS first_approval_seconds,
    BIGINT(
        UNIX_TIMESTAMP(pr.ts_merged) - UNIX_TIMESTAMP(cms.first_approval_ts)
    )                                           AS merge_after_approval_seconds,
    BIGINT(
        UNIX_TIMESTAMP(cms.first_human_comment_ts) - UNIX_TIMESTAMP(pr.ts_created)
    )                                           AS human_review_wait_seconds,
    BIGINT(
        UNIX_TIMESTAMP(cms.first_human_approval_ts) - UNIX_TIMESTAMP(pr.ts_created)
    )                                           AS human_first_approval_seconds,

    CAST(pr.ts_created AS DATE)                 AS dt_created,
    CAST(pr.ts_merged AS DATE)                  AS dt_merged,
    CAST(pcm.ts_released AS DATE)               AS dt_released,
    CAST(cs.first_commit_ts AS DATE)            AS dt_first_commit,
    CAST(cs.last_commit_ts AS DATE)             AS dt_last_commit,
    CAST(cms.first_comment_ts AS DATE)          AS dt_first_comment,
    CAST(cms.first_approval_ts AS DATE)         AS dt_first_approval,
    CAST(cms.first_human_comment_ts AS DATE)    AS dt_first_human_comment,
    CAST(cms.first_human_approval_ts AS DATE)   AS dt_first_human_approval,
    CURRENT_TIMESTAMP()                         AS ts_load
FROM
    datalake_devlake_clean.pull_requests AS pr
LEFT JOIN
    datalake_devlake_clean.pr_custom_metrics AS pcm
    ON pr.id_pr = pcm.id_pr
LEFT JOIN
    primary_team AS pt
    ON pr.id_repo = pt.id_repo
    AND pr.pr_key = pt.pr_key
LEFT JOIN
    commit_stats AS cs
    ON pr.id_pr = cs.id_pr
LEFT JOIN
    comment_stats AS cms
    ON pr.id_pr = cms.id_pr
