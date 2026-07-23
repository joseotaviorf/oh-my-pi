WITH main_users AS (
    SELECT
        id AS sk_user,
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
users_ranked AS (
    SELECT
        v.id AS sk_visitor,
        COALESCE(v.id_external, u_email.sk_user,u_phone.sk_user) AS sk_user,
        COALESCE(v.email, u_email.email, u_phone.email) AS email,
        COALESCE(v.phone_number,u_email.main_phone, u_phone.main_phone) AS phone_number,
        v.ts_updated,
        ROW_NUMBER() OVER(PARTITION BY v.id ORDER BY v.ts_updated DESC) AS rn
    FROM
        datalake_hub_services_clean.visitor AS v
    LEFT JOIN
        main_users AS u_email
            ON UPPER(TRIM(u_email.email)) = UPPER(TRIM(v.email)) AND COALESCE(v.id_external,0) = 0
    LEFT JOIN
        main_users AS u_phone
            ON TRIM(u_phone.main_phone) = TRIM(REPLACE(phone_number,'+','')) AND COALESCE(v.id_external, 0) = 0
),
users AS (
    SELECT
        sk_visitor,
        sk_user,
        email,
        phone_number,
        ts_updated
    FROM
        users_ranked
    WHERE
        rn = 1
),
hs_users_ranked AS (
  SELECT
      id AS id_user,
      id_external,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rn
  FROM
      datalake_hub_services_clean.users
),
hs_users AS (
  SELECT
      id_user,
      id_external
  FROM
      hs_users_ranked
  WHERE
      rn = 1
),
main_leads AS (
    SELECT
        l.id_visitor,
        l.id AS id_lead,
        l.id_house,
        l.id_business_unit,
        l.lead_status,
        u.sk_user,
        l.ts_created,
        ROW_NUMBER() OVER(PARTITION BY u.sk_user, l.id, l.id_house ORDER BY l.ts_updated DESC) AS rw
    FROM
        datalake_hub_services_clean.lead AS l
    LEFT JOIN
        users AS u
            ON l.id_visitor = u.sk_visitor
    WHERE
        business_context = 'SALE'
),
leads AS (
    SELECT
        sk_user,
        id_visitor,
        id_lead,
        id_house,
        id_business_unit,
        lead_status,
        ts_created,
        ROW_NUMBER() OVER(PARTITION BY sk_user ORDER BY ts_created) AS first_house_marker
    FROM
        main_leads
    WHERE
        rw = 1
),
assignment_order AS (
    SELECT
        l1.sk_user,
        r.id_responsible,
        r.ts_assigned,
        l2.id_house AS id_first_house,
        l1.id_house AS id_last_house,
        l2.ts_created AS date_contact,
        l2.lead_status,
        ROW_NUMBER() OVER(PARTITION BY l1.sk_user ORDER BY r.ts_assigned ASC) first_assignment_marker,
        ROW_NUMBER() OVER(PARTITION BY l1.sk_user ORDER BY r.ts_assigned DESC) last_assignment_marker
    FROM
        datalake_hub_services_clean.responsible AS r
    INNER JOIN
        leads AS l1
            ON r.id_lead = l1.id_lead
    LEFT JOIN
        leads AS l2
            ON l1.sk_user = l2.sk_user
            AND l2.first_house_marker = 1
),
responsible AS (
    SELECT
        a1.sk_user,
        a1.id_first_house,
        a1.id_last_house,
        a1.date_contact,
        a1.id_responsible AS last_responsible_id,
        sh.id_secretariat_user AS last_secretariat_user,
        a2.ts_assigned AS ts_first_assignment,
        a1.ts_assigned AS ts_last_assignment
    FROM
        assignment_order AS a1
    LEFT JOIN
        assignment_order AS a2
            ON a1.sk_user = a2.sk_user
            AND a2.first_assignment_marker = 1
    LEFT JOIN
        hs_users AS u
            ON a1.id_responsible = u.id_user
    LEFT JOIN
        datalake_secretariat.secretariat_allocation_history AS sh
            ON sh.id_secretariat_user = u.id_external
            AND sh.is_last_version IS TRUE
            AND sh.is_active IS TRUE
    WHERE
        a1.last_assignment_marker = 1
)
SELECT
    sk_user,
    last_responsible_id AS id_responsible,
    last_secretariat_user AS sk_user_last_secretariat,
    ts_first_assignment AS ts_assigned_started,
    ts_last_assignment AS ts_assigned_ended
FROM
    responsible
WHERE
    sk_user IS NOT NULL
    AND last_secretariat_user IS NOT NULL
