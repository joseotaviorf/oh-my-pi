WITH last_updated_agents AS (
    SELECT
        a.id AS id_agent,
        CAST(GET_JSON_OBJECT(a.details, '$.userExternalId') AS LONG) AS id_user,
        CAST(GET_JSON_OBJECT(a.details, '$.partnerExternalId') AS LONG) AS id_partner,
        CAST(GET_JSON_OBJECT(a.details, '$.active') AS BOOLEAN) AS is_active_in_big_agent,
        a.ts_created,
        a.ts_updated
    FROM
        datalake_big_agent_clean.agent AS a
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY GET_JSON_OBJECT(a.details, '$.partnerExternalId') ORDER BY a.ts_updated DESC) = 1
),
partner_agent AS (
    SELECT
        p.id,
        p.name,
        p.phone,
        p.cnpj,
        p.email,
        p.creci,
        p.type,
        pa.status,
        p.ts_created,
        p.ts_updated,
        pa.ts_updated AS ts_status_updated
    FROM
        datalake_ebdb_clean.partner AS p
    LEFT JOIN datalake_ebdb_clean.partner_agent AS pa 
        ON pa.id_partner = p.id
    WHERE p.type = 'AUTONOMOUS_AGENT'    
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY p.id ORDER BY pa.ts_updated DESC) = 1
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
    u.id AS id_main_user,
    CAST(u.id_agent AS INTEGER) AS id_agent_data,
    hs.id_hub_services_user,
    u.name,
    u.email,
    u.main_phone,
    ad.creci_number,
    u.cpf,
    u.city,
    pa.status,
    a.ts_created AS ts_agent_created,
    a.ts_updated AS ts_agent_updated,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated
FROM
    last_updated_agents AS a
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.id = a.id_user
LEFT JOIN
    datalake_ebdb_user.agent_data AS ad
        ON ad.id = u.id_agent
LEFT JOIN 
    partner_agent AS pa
        ON a.id_partner = pa.id
LEFT JOIN 
    hub_services_users AS hs
        ON u.id = hs.id_main_user