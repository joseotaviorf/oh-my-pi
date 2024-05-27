WITH users AS (
    SELECT
        u.id_user,
        u.id_main_user,
        u.id_agent
    FROM
        datalake_hub_services.users AS u
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY u.ts_updated DESC) = 1
)
SELECT
    mp.id_member_profile AS sk_member_profile,
    mp.id_member_relationship AS sk_member_relationship,
    mp.id_user AS sk_user,
    u.id_agent AS sk_agent,
    mp.id_parent_member_profile AS sk_parent_member_profile,
    mp.id_parent_user AS sk_parent_user,
    p.id_profile AS sk_profile,
    mp.id_business_unit AS sk_business_unit,
    mp.is_active,
    mp.profile = 'AGENT' AS is_agent,
    mp.profile = 'NEGOTIATION_EXECUTIVE' AS is_negotiation_executive,
    mp.profile LIKE '%SECRETARIAT%' AS is_secretariat_member,
    mp.ts_relationship_started,
    mp.ts_relationship_ended,
    NOW() AS ts_load
FROM
    datalake_hub_services.member_profile AS mp
JOIN
    datalake_hub_services.profile AS p
        ON p.profile = mp.profile
LEFT JOIN
    users AS u
        ON u.id_user = mp.id_user