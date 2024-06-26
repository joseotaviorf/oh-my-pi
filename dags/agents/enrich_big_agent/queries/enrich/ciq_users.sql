WITH partner_type AS (
   SELECT
        p.id, -- id_partner
        p.type,
        p.ts_updated
    FROM
        datalake_ebdb_clean.partner AS p
    WHERE 
        p.type = 'AUTONOMOUS_AGENT'    -- Type for CIQ user
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY p.id ORDER BY p.ts_updated DESC) = 1
),
big_agent_enrollment_type AS (
    SELECT 
        id_agent,
        id_program,
        ts_updated
    FROM
        datalake_big_agent_clean.enrollment 
    WHERE 
        id_program IN (1,2) -- CIQ Manager or CIQ Full
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_agent ORDER BY ts_updated DESC) = 1
),
updated_id_user_main AS (
    SELECT
      id_user,
      EXPLODE(predecessor_user_list) AS id_predecessor_user
    FROM
      datalake_ebdb_user.user_merge
),
ciq_agents AS (
    SELECT
        a.id AS id_agent,
        CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS LONG) AS id_user,
        CAST(GET_JSON_OBJECT(a.details, '$.partnerExternalId') AS LONG) AS id_partner,
        CAST(GET_JSON_OBJECT(a.details, '$.active') AS BOOLEAN) AS is_active,
        COALESCE(uim.id_user, CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS LONG)) AS id_main_user,
        CASE 
          WHEN uim.id_user IS NOT NULL THEN TRUE
          ELSE FALSE
        END is_user_merged,
        e.id_program,
        a.ts_created,
        a.ts_updated
    FROM
        datalake_big_agent_clean.agent AS a
    LEFT JOIN
        partner_type AS pt
        ON CAST(GET_JSON_OBJECT(a.details, '$.partnerExternalId') AS LONG) = pt.id
    LEFT JOIN
        big_agent_enrollment_type AS e 
            ON e.id_agent = a.id
    LEFT JOIN
        updated_id_user_main AS uim
            ON CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS LONG) = uim.id_predecessor_user
    WHERE 
        e.id_program IS NOT NULL   -- CIQ Manager or CIQ Full
        OR pt.type IS NOT NULL     -- pt.type = 'AUTONOMOUS_AGENT' is a CIQ Agent        
),
hub_services_users AS (
    SELECT
        id_user AS id_hub_services_user,
        id_main_user,
        id_agent
    FROM
        datalake_hub_services.users
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_updated DESC) = 1
)
SELECT 
    a.id_agent,
    a.id_partner,
    a.id_main_user,
    CAST(u.id_agent AS INTEGER) AS id_agent_data,
    hs.id_hub_services_user,
    u.name,
    u.email,
    a.is_active,
    a.is_user_merged,   
    a.ts_created AS ts_agent_created,
    a.ts_updated AS ts_agent_updated_start,
    LEAD(a.ts_updated) OVER (PARTITION BY a.id_agent ORDER BY a.ts_updated ASC) AS ts_agent_updated_end
FROM
    ciq_agents AS a
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.id = a.id_main_user
LEFT JOIN 
    hub_services_users AS hs
        ON u.id = hs.id_main_user