WITH sources AS (
    SELECT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.usage_daily
    UNION ALL
    SELECT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.spend_daily
    UNION ALL
    SELECT
        'claude' AS tool,
        id_user,
        email_user
    FROM
        datalake_claude_usage_clean.user_activity
    UNION ALL
    SELECT
        'claude' AS tool,
        id AS id_user,
        email AS email_user
    FROM
        datalake_claude_usage_clean.members
    UNION ALL
    SELECT
        'claude' AS tool,
        id_user,
        email_actor AS email_user
    FROM
        datalake_claude_usage_clean.spend_limits
    WHERE
        id_user IS NOT NULL
),
ai_users AS (
    SELECT
        tool,
        id_user,
        email_user,
        ROW_NUMBER() OVER (
            PARTITION BY
                tool,
                id_user
            ORDER BY
                CASE
                    WHEN id_user IS NOT NULL AND email_user IS NOT NULL THEN 0
                    ELSE 1
                END
        ) AS rn
    FROM
        sources
),
deduped AS (
    SELECT
        tool,
        id_user,
        email_user
    FROM
        ai_users
    WHERE
        rn = 1
)
SELECT
    MD5(CONCAT_WS(',', deduped.tool, deduped.id_user)) AS sk_ai_user,
    deduped.tool,
    deduped.id_user,
    deduped.email_user
FROM
    deduped
