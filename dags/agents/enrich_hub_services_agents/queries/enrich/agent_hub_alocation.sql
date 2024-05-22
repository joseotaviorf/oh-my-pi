WITH users AS (
    SELECT DISTINCT
        u.id_user,
        u.id_main_user,
        u.id_agent,
        u.name,
        u.email,
        u.phone_number
    FROM
        datalake_hub_services.users AS u
    QUALIFY 
        u.ts_updated = MAX(u.ts_updated) OVER(PARTITION BY u.id_user)
)
SELECT
    mp.id_member_profile,
    u.id_main_user AS id_user,
    u.id_agent,
    mp.id_parent_member_profile AS id_member_profile_negotiation_executive,
    u_parent.id_main_user AS id_user_negotiation_executive,
    mp.id_business_unit,
    bu.hub_name,
    bu.business_context,
    ad.agent_type,
    u.name AS agent_name,
    u.email AS agent_email,
    u.phone_number AS agent_phone_number,
    u_parent.name AS negotiation_executive_name,
    u_parent.email AS negotiation_executive_email,
    u_parent.phone_number AS negotiation_executive_phone_number,
    aux_date.date AS dt_reference,
    aux_date.year,
    aux_date.month,
    aux_date.day
FROM
    datalake_hub_services.member_profile AS mp
JOIN
    datalake_quintoandar.aux_date
        ON aux_date.date BETWEEN DATE(mp.ts_relationship_started) 
        AND DATE(COALESCE(mp.ts_relationship_ended, mp.ts_load))
LEFT JOIN
    users AS u
        ON u.id_user = mp.id_user
LEFT JOIN
    users AS u_parent
        ON u_parent.id_user = mp.id_parent_user
LEFT JOIN
    datalake_hub_services_clean.business_unit AS bu
        ON bu.id = mp.id_business_unit
LEFT JOIN
    datalake_ebdb_clean.agent_data AS ad
        ON ad.id = u.id_agent
WHERE
    mp.profile = 'AGENT'
    AND aux_date.date = MAKE_DATE({year}, {month}, {day})