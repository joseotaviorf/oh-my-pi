WITH base_phones AS (
    SELECT DISTINCT
        p.uuid_person,
        ci.contact_info AS phone
    FROM
        datalake_rental_guarantee_platform_clean.company co
    LEFT JOIN
        datalake_company_clean.company c
          ON c.uuid_company = co.uuid_company
    LEFT JOIN
        datalake_company_clean.member_profile mp
          ON c.id = mp.id_company
    LEFT JOIN
        datalake_person_clean.person p
          ON mp.uuid_person = p.uuid_person
    LEFT JOIN
        datalake_person_clean.contact_info ci
          ON p.id = ci.id_person
          AND ci.category = 'PHONE'
)
    SELECT DISTINCT
        b.id_broker,
        u.uuid_user AS id_realtor,
        b.broker_name,
        b.broker_comercial_name,
        b.cnpj AS document,
        u.name AS realtor,
        u.email,
        t.phone AS phone,
        u.user_role AS profile
    FROM
        datalake_velo.propose p
    LEFT JOIN
        datalake_velo.broker b
          ON b.id_broker = p.id_broker
    LEFT JOIN
        datalake_velo.user u
          ON u.id_user = p.id_agent
    LEFT JOIN
        base_phones t
          ON t.uuid_person = u.uuid_user
