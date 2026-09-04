WITH ai_users AS (
    SELECT DISTINCT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.usage_daily
    UNION
    SELECT DISTINCT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.spend_daily
)
SELECT
    MD5(CONCAT_WS(',', ai_users.tool, ai_users.id_user)) AS sk_ai_user,
    ai_users.tool,
    ai_users.id_user,
    ai_users.email_user
FROM
    ai_users
