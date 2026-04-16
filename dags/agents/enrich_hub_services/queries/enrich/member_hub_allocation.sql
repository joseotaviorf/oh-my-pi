WITH member_profile AS (
    SELECT
        mp.id_member_relationship,
        mp.id_member_profile,
        mp.id_user,
        mp.id_parent_member_profile,
        mp.id_parent_user,
        mp.id_business_unit,
        mp.profile,
        mp.ts_relationship_started,
        CASE
            WHEN mp.ts_relationship_ended IS NULL THEN mp.ts_load
            ELSE mp.ts_relationship_ended - INTERVAL 1 DAY 
        END AS ts_relationship_ended
    FROM
        datalake_hub_services.member_profile AS mp
)
SELECT
    mp.id_member_profile,
    mp.id_user,
    u.id_main_user AS id_main_user,
    u.id_agent,
    u.uuid_person,
    ad.uuid_company,
    mp.id_parent_member_profile,
    mp.id_parent_user,
    u_parent.id_main_user AS id_parent_main_user,
    u_parent.id_agent AS id_parent_agent,
    u_parent.uuid_person AS uuid_parent_person,
    mp.id_business_unit,
    bu.hub_name,
    bu.city_group,
    bu.city_name,
    bu.short_region_name,
    bu.lead_types,
    bu.business_context,
    mp.profile,
    ad.agent_type,
    u.name AS user_name,
    u.email AS user_email,
    u.phone_number AS user_phone_number,
    u.secondary_phone_number AS user_secondary_phone_number,
    u.cpf AS user_cpf,
    u_parent.name AS user_parent_name,
    u_parent.email AS user_parent_email,
    u_parent.phone_number AS user_parent_phone_number,
    u_parent.secondary_phone_number AS user_parent_secondary_phone_number,
    u_parent.cpf AS user_parent_cpf,
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
    datalake_ebdb_clean.agent_data AS ad
        ON ad.id = u.id_agent
LEFT JOIN
    datalake_hub_services.business_unit AS bu
        ON bu.id_business_unit = mp.id_business_unit
        AND bu.is_last_region_associated IS TRUE
WHERE
    MAKE_DATE(aux_date.year, aux_date.month, aux_date.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')