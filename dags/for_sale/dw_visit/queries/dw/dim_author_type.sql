SELECT
    ROW_NUMBER() OVER (ORDER BY author_type_seq.sk_seq, author_role_seq.sk_seq, on_behalf_seq.sk_seq, channel_seq.sk_seq) AS sk_author_type,
    author_type,
    author_user_role,
    on_behalf_of,
    channel,
    NOW() AS ts_load
FROM
(
    SELECT 1 AS sk_seq, 'PERSON' AS author_type
    UNION ALL
    SELECT 2 AS sk_seq, 'USUARIO' AS author_type
) AS author_type_seq
CROSS JOIN
(
    SELECT 1 AS sk_seq, 'AGENT' AS author_user_role
    UNION ALL
    SELECT 2 AS sk_seq, 'DEMAND' AS author_user_role
    UNION ALL
    SELECT 3 AS sk_seq, 'OPS' AS author_user_role
    UNION ALL
    SELECT 4 AS sk_seq, 'SUPPLY' AS author_user_role
    UNION ALL
    SELECT 5 AS sk_seq, NULL AS author_user_role
    UNION ALL
    SELECT 6 AS sk_seq, 'TENANT_LIVING' AS author_user_role
) AS author_role_seq
CROSS JOIN
(
    SELECT 1 AS sk_seq, 'AGENT' AS on_behalf_of
    UNION ALL
    SELECT 2 AS sk_seq, 'DEMAND' AS on_behalf_of
    UNION ALL
    SELECT 3 AS sk_seq, 'SUPPLY' AS on_behalf_of
    UNION ALL
    SELECT 4 AS sk_seq, 'TENANT_LIVING' AS on_behalf_of
) AS on_behalf_seq
CROSS JOIN
(
    SELECT 1 AS sk_seq, 'OWNER_PWA' AS channel
    UNION ALL
    SELECT 2 AS sk_seq, 'TENANT_PWA' AS channel
    UNION ALL
    SELECT 3 AS sk_seq, 'WHATSAPP' AS channel
    UNION ALL
    SELECT 4 AS sk_seq, 'MAGIC_LINK' AS channel
    UNION ALL
    SELECT 5 AS sk_seq, 'TENANT_NATIVE' AS channel
    UNION ALL
    SELECT 6 AS sk_seq, 'AGENT_PWA' AS channel
    UNION ALL
    SELECT 7 AS sk_seq, 'PORTFOLIO_MANAGER' AS channel
    UNION ALL
    SELECT 8 AS sk_seq, 'SYSTEM' AS channel
) AS channel_seq
