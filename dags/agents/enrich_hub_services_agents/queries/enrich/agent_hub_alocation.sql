WITH member_profile AS (
    SELECT
        mp.id_member_relationship,
        mp.id_member_profile,
        mp.id_user,
        mp.id_parent_member_profile,
        mp.id_parent_user,
        mp.id_business_unit,
        mp.ts_relationship_started,
        CASE
            WHEN mp.ts_relationship_ended IS NULL THEN mp.ts_load
            ELSE mp.ts_relationship_ended - INTERVAL 1 DAY 
        END AS ts_relationship_ended
    FROM
        datalake_hub_services.member_profile AS mp
    WHERE
        mp.profile = 'AGENT'
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
    member_profile AS mp
JOIN
    datalake_quintoandar.aux_date
        ON aux_date.date BETWEEN DATE(mp.ts_relationship_started) AND DATE(mp.ts_relationship_ended)
LEFT JOIN
    datalake_hub_services.users AS u
        ON u.id_user = mp.id_user
LEFT JOIN
    datalake_hub_services.users AS u_parent
        ON u_parent.id_user = mp.id_parent_user
LEFT JOIN
    datalake_hub_services_clean.business_unit AS bu
        ON bu.id = mp.id_business_unit
LEFT JOIN
    datalake_ebdb_clean.agent_data AS ad
        ON ad.id = u.id_agent
WHERE
    aux_date.year = {year}
    AND aux_date.month = {month}
    AND aux_date.day = {day}