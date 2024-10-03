SELECT
    MD5(a.email) AS sk_analyst,
    a.name AS full_name,
    a.email,
    a.phone,
    CASE
        WHEN a.organization = 'atn' THEN 'atento'
        WHEN a.organization = 'quintoandar.com' THEN 'quintoandar'
        WHEN a.organization = 'webhelpbr' THEN 'webhelp'
        WHEN a.organization = 'contractors' THEN 'webhelp'
        ELSE a.organization
    END agent_organization,
    ac.manager AS agent_manager,
    DATE(a.ts_created) AS dt_agent_start,
    NOW() AS ts_load
FROM
    datalake_support_users.analysts AS a
LEFT JOIN
    datalake_gsheets_clean.agents_control AS ac
        ON LOWER(a.email) = LOWER(ac.email)
