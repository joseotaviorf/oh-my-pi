SELECT
    mp.id_member_relationship,
    mp.id_member_profile,
    mp.id_user,
    mp.id_main_user,
    mp.id_agent,
    mp.uuid_person,
    mp.uuid_company,
    mp.id_parent_member_profile,
    mp.id_parent_user,
    mp.id_business_unit,
    mp.id_parent_main_user,
    mp.id_parent_agent,
    mp.uuid_parent_person,
    mp.id_region,
    mp.profile,
    mp.agent_type,
    mp.hub_name,
    mp.city_group,
    mp.city_name,
    mp.short_region_name,
    mp.lead_types,
    mp.business_context,
    mp.name AS user_name,
    mp.email AS user_email,
    mp.phone_number AS user_phone_number,
    mp.secondary_phone_number AS user_secondary_phone_number,
    mp.cpf AS user_cpf,
    mp.parent_name AS parent_name,
    mp.parent_email AS parent_email,
    mp.parent_phone_number AS parent_phone_number,
    mp.parent_secondary_phone_number,
    mp.parent_cpf AS parent_cpf,
    mp.is_member_active_in_period AS is_active,
    aux_date.date AS dt_reference,
    aux_date.year,
    aux_date.month,
    aux_date.day
FROM
    datalake_hub_services.member_profile AS mp
JOIN
    datalake_quintoandar.aux_date
        ON aux_date.date BETWEEN DATE(mp.ts_relationship_started) 
            AND DATE(mp.ts_relationship_ended)
WHERE
    MAKE_DATE(aux_date.year, aux_date.month, aux_date.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY     
    1 = ROW_NUMBER() OVER(
        PARTITION BY mp.id_member_profile, aux_date.date
        ORDER BY mp.ts_relationship_started DESC, mp.ts_relationship_ended DESC
    )