SELECT
    MD5(a.email) AS sk_analyst,
    u.id AS sk_user,
    u.uuid_person,
    a.id_agent_twilio AS sk_agent_twilio,
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
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.email = a.email
        AND u.country_code = 'BR'
