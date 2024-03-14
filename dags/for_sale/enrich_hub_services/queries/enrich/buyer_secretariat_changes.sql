WITH users_5a AS (
    SELECT
        id AS id_user,
        LOWER(email) AS email,
        REPLACE(main_phone,'+','') AS main_phone
    FROM
        datalake_ebdb_clean.user
    WHERE
        LENGTH(REPLACE(main_phone,'+','')) IN (12,13)
        AND SUBSTRING(main_phone,1,3) = '+55'
        AND TRY_CAST(SUBSTRING(main_phone,4,2) AS INT) BETWEEN 11 AND 99
        AND TRY_CAST(SUBSTRING(main_phone,6,1) AS INT) BETWEEN 2 AND 9
        AND TRY_CAST(SUBSTRING(main_phone,6,9) AS INT) NOT IN (111111111,222222222,333333333,444444444,555555555,666666666,777777777,888888888,999999999)
        AND TRY_CAST(SUBSTRING(main_phone,6,8) AS INT) NOT IN (11111111,22222222,33333333,44444444,55555555,66666666,77777777,88888888,99999999)
),
visitor AS (
    SELECT
        v.id,
        COALESCE(v.id_external, u_email.id_user,u_phone.id_user) AS id_external,
        COALESCE(v.email, u_email.email, u_phone.email) AS visitor_email,
        visitor_name
    FROM
        datalake_hub_services_clean.visitor AS v
    LEFT JOIN
        users_5a AS u_email
            ON COALESCE(v.id_external,0) = 0
            AND UPPER(TRIM(u_email.email)) = UPPER(TRIM(v.email))
    LEFT JOIN
        users_5a AS u_phone
            ON COALESCE(v.id_external, 0) = 0
            AND TRIM(u_phone.main_phone) = TRIM(REPLACE(phone_number,'+',''))
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY COALESCE(v.id_external, u_email.id_user,u_phone.id_user), v.id ORDER BY version DESC) = 1
),
leads AS (
    SELECT
        le.id AS id_lead,
        le.id_visitor,
        vi.id_external,
        le.id_house,
        le.id_business_unit,
        le.lead_type,
        visitor_name,
        visitor_email
    FROM
        datalake_hub_services_clean.lead AS le
    LEFT JOIN
        visitor AS vi
            ON vi.id = le.id_visitor
),
events_aud AS (
    SELECT
        re.id_lead,
        re.is_active,
        le.id_visitor,
        le.id_external AS id_external_lead,
        resp_u.id_external AS id_external_responsible,
        dist_u.id_external AS id_external_distributor,
        le.id_house,
        le.id_business_unit,
        re.id_responsible,
        re.id_distributor,
        le.lead_type,
        le.visitor_name,
        le.visitor_email,
        resp_u.email AS responsible_email,
        dist_u.email AS distributor_email,
        re.ts_assigned,
        re.ts_unassigned
    FROM
        datalake_hub_services_clean.responsible AS re
    LEFT JOIN
        leads AS le
            ON le.id_lead = re.id_lead
    LEFT JOIN
        datalake_hub_services_clean.users AS resp_u
            ON re.id_responsible = resp_u.id
    LEFT JOIN
        datalake_hub_services_clean.users AS dist_u
            ON re.id_distributor = dist_u.id
)
SELECT
    ev.id_lead,
    ev.id_external_lead,
    id_external_responsible,
    id_external_distributor,
    ev.id_house,
    ev.id_business_unit,
    ev.lead_type,
    ev.visitor_name,
    ev.visitor_email,
    ev.responsible_email,
    ev.distributor_email,
    ROW_NUMBER() OVER(PARTITION BY COALESCE(id_external_lead, id_lead) ORDER BY is_active DESC, ts_assigned DESC) = 1 AS is_last_responsible,
    ev.is_active,
    ev.ts_assigned,
    ev.ts_unassigned
FROM
    events_aud AS ev
