WITH last_member_profile AS (
    SELECT
        id_user,
        id_business_unit,
        profile,
        is_active,
        dt_relationship_started
    FROM
        datalake_hub_services_clean.member_profile
    WHERE
        profile LIKE '%SECRETARIAT%'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_created DESC, ts_updated DESC) = 1
),
last_business_unit AS (
    SELECT
        id,
        hub_name
    FROM
        datalake_hub_services_clean.business_unit
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),
hub_services_secretariat AS (
    SELECT
        u.id AS id_user_hub_services,
        u.id_external AS id_user_5a,
        bu.id AS id_business_unit,
        u.name,
        u.email,
        bu.hub_name AS allocation,
        mp.profile AS member_profile,
        mp.is_active,
        mp.dt_relationship_started
    FROM 
        datalake_hub_services_clean.users AS u
    LEFT JOIN
        last_member_profile AS mp ON
            u.id = mp.id_user
    LEFT JOIN
        last_business_unit AS bu
            ON mp.id_business_unit = bu.id
    WHERE
        bu.hub_name NOT LIKE '[For rent]%'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY u.id_external ORDER BY u.ts_updated DESC, mp.is_active DESC) = 1
),
legacy_secretariat AS (
    SELECT
        NULL::BIGINT AS id_user_hub_services,
        id_user_5a,
        NULL::BIGINT AS id_business_unit,
        secretariat_name AS name,
        email,
        allocation,
        NULL::STRING AS member_profile,
        status = 'Ativo' AS is_active,
        dt_started AS dt_relationship_started
    FROM
        datalake_gsheets_clean.secretariat_hierarchy
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user_5a ORDER BY dt_relationship_started) = 1
)
SELECT
    COALESCE(hss.id_user_hub_services, ls.id_user_hub_services) AS id_user_hub_services,
    COALESCE(hss.id_user_5a, ls.id_user_5a) AS id_user_5a,
    COALESCE(hss.id_business_unit, ls.id_business_unit) AS id_business_unit,
    COALESCE(hss.name, ls.name) AS name,
    COALESCE(hss.email, ls.email) AS email,
    COALESCE(hss.allocation, ls.allocation) AS allocation,
    CASE
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%HUB%' THEN 'HUB'
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%Growth%' THEN 'Growth'
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%3P%' THEN '3P'
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%CENTRAL%' THEN 'Central'
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%Lite%' THEN 'NBP'
        WHEN COALESCE(hss.allocation, ls.allocation) LIKE '%BWA%' THEN 'BWA'
        ELSE 'Other'
    END AS segment,
    COALESCE(hss.member_profile, ls.member_profile) AS member_profile,
    COALESCE(hss.is_active, ls.is_active) AS is_active,
    COALESCE(hss.dt_relationship_started, ls.dt_relationship_started) AS dt_relationship_started
FROM
    hub_services_secretariat AS hss
FULL OUTER JOIN
    legacy_secretariat AS ls
        ON hss.id_user_5a = ls.id_user_5a
