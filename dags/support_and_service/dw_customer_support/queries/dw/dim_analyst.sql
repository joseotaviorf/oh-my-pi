WITH clean_email AS (
    SELECT 
        CASE
            WHEN LENGTH(SPLIT(a.email, '\\.')[SIZE(SPLIT(a.email, '\\.')) - 1]) = 1
                AND SPLIT(a.email, '\\.')[SIZE(SPLIT(a.email, '\\.')) - 1] LIKE 'b%'
            THEN CONCAT(a.email, 'r')
            ELSE a.email
        END AS email,
        a.name AS full_name,
        a.phone,
        CASE
            WHEN a.organization = 'atn' THEN 'atento'
            WHEN a.organization = 'quintoandar.com' THEN 'quintoandar'
            WHEN a.organization = 'webhelpbr' THEN 'webhelp'
            WHEN a.organization = 'contractors' THEN 'webhelp'
            ELSE a.organization
        END AS agent_organization,
        DATE(a.ts_created) AS dt_agent_start
    FROM
        datalake_support_users.analysts AS a
),
ranked_analysts AS (
    SELECT
        MD5(ce.email) AS sk_analyst,
        u.id AS sk_user,
        u.uuid_person,
        a.id_agent_twilio AS sk_agent_twilio,
        ce.full_name,
        ce.email,
        ce.phone,
        ce.agent_organization,
        ac.manager AS agent_manager,
        ce.dt_agent_start,
        NOW() AS ts_load,
        ROW_NUMBER () OVER (PARTITION BY ce.email ORDER BY dt_agent_start ASC) AS rn
    FROM
        clean_email AS ce
    LEFT JOIN
        datalake_support_users.analysts AS a
            ON a.email = ce.email
    LEFT JOIN
        datalake_gsheets_clean.agents_control AS ac
            ON LOWER(ce.email) = LOWER(ac.email)
    LEFT JOIN
        datalake_ebdb_user.user AS u
            ON u.email = ce.email
            AND u.country_code = 'BR'
)
SELECT
    sk_analyst,
    sk_user,
    uuid_person,
    sk_agent_twilio,
    full_name,
    email,
    phone,
    agent_organization,
    agent_manager,
    dt_agent_start,
    ts_load
FROM
    ranked_analysts
WHERE
    rn = 1
