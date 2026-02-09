WITH users_ AS (
    SELECT
        id AS id_user,
        id_agent,
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
visitors_reference_table AS (
    SELECT
        v.id AS id_visitor,
        COALESCE(v.id_external, u_email.id_user,u_phone.id_user) AS id_user,
        COALESCE(v.email, u_email.email, u_phone.email) AS email,
        COALESCE(v.phone_number,u_email.main_phone, u_phone.main_phone) AS phone_number,
        v.ts_created,
        v.ts_updated
    FROM
        datalake_hub_services_clean.visitor AS v
    LEFT JOIN
        datalake_hub_services_clean.lead AS l
            ON v.id = l.id_visitor
    LEFT JOIN
        datalake_hub_services_clean.responsible AS hr
            ON l.id = hr.id_lead
            AND hr.is_active
    LEFT JOIN
        users_ AS u_email
            ON COALESCE(v.id_external,0) = 0
            AND UPPER(TRIM(u_email.email)) = UPPER(TRIM(v.email))
    LEFT JOIN
        users_ AS u_phone
            ON COALESCE(v.id_external, 0) = 0
            AND TRIM(u_phone.main_phone) = TRIM(REPLACE(phone_number,'+',''))
    QUALIFY
        ROW_NUMBER() OVER(
            PARTITION BY
                v.id
            ORDER BY
                v.ts_updated DESC
        ) = 1
),
users_reference_table AS (
    SELECT
        id_visitor,
        id_user,
        email,
        phone_number,
        ts_created,
        ts_updated
    FROM
        visitors_reference_table
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY COALESCE(id_user, id_visitor) ORDER BY ts_updated DESC) = 1
),
hs_users_reference_table AS (
    SELECT
        u.id_external AS id_user,
        u.id AS id_user_hub_services,
        u.name,
        u.email,
        sh.allocation,
        sh.segment
    FROM
        datalake_hub_services_clean.users AS u
    LEFT JOIN
        datalake_hub_services.secretariat_hierarchy AS sh
            ON u.id_external = sh.id_user_5a
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY COALESCE(u.id_external, u.id) ORDER BY u.ts_created DESC, u.ts_updated DESC) = 1
),
responsible_reference_table AS (
    SELECT
        id_lead,
        id_responsible AS id_user_hub_services
    FROM
        datalake_hub_services_clean.responsible AS r
    WHERE
        is_active
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_lead ORDER BY r.ts_created DESC, r.ts_updated DESC) = 1
),
leads_reference_table AS (
    SELECT
        l.id AS id_lead,
        IF(LENGTH(id_house) < 9, 892700000 + id_house, id_house) AS id_house,
        l.id_visitor,
        trr.id_user_hub_services AS id_user_hub_services_responsible,
        vr.id_user,
        l.lead_type,
        l.ts_created,
        l.ts_updated
    FROM
        datalake_hub_services_clean.lead AS l
    JOIN
        responsible_reference_table AS trr
            ON trr.id_lead = l.id
    LEFT JOIN
        visitors_reference_table AS vr
            ON l.id_visitor = vr.id_visitor
    WHERE
        business_context = 'SALE'
        AND lead_type <> 'AGENT_REDE'
),
last_lead AS (
  SELECT
      id_lead,
      id_visitor,
      id_user_hub_services_responsible,
      id_user,
      id_house,
      lead_type AS last_contact_prospect_origin,
      ts_created AS ts_last_contact_prospect
  FROM
      leads_reference_table
  QUALIFY
      ROW_NUMBER() OVER(PARTITION BY COALESCE(id_user, id_visitor) ORDER BY ts_created DESC) = 1
),
first_lead AS (
    SELECT
        id_lead,
        id_visitor,
        id_user,
        id_house,
        CASE
              WHEN lead_type IN ('CONTATO') THEN 'Visit Intent Clicked'
              WHEN lead_type IN ('CLASSIFIED') THEN 'Classificados'
              WHEN lead_type IN ('TALK_TO_SECRETARIA','TALK_TO_SECRETARIA_BH') THEN 'TTS'
              WHEN lead_type IN ('SIGN') THEN 'Plaquinhas'
              WHEN lead_type IN ('TQC_5A') THEN 'TQC'
              WHEN lead_type IN ('TALK_TO_SECRETARIA_PRIMARY_MARKET') THEN 'TTS - PRIMARIO'
              WHEN lead_type IN ('INBOUND') THEN 'Inbound'
              WHEN lead_type IN ('EVENT_COMBO') THEN 'Combo de Eventos'
              ELSE 'Other'
        END AS first_contact_prospect_origin,
        ts_created AS ts_first_contact_prospect
    FROM
        leads_reference_table
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY COALESCE(id_user, id_visitor) ORDER BY ts_created ASC) = 1
),
house_region AS (
    SELECT
        tur.id_user,
        tur.id_visitor,
        dr.city_group AS region
    FROM
        users_reference_table AS tur
    LEFT JOIN
        first_lead AS fl
            ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(fl.id_user, fl.id_visitor)
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON fl.id_house = h.id
    LEFT JOIN
        datalake_gsheets_clean.auxiliary_region AS dr
            ON h.id_region = dr.id
),
bookings_reference_table AS (
    SELECT 
        id_visitor AS id_user,
        id AS id_booking,
        id_attendant,
        user_sale_booking_creator,
        status,
        is_visit_completed,
        ts_created,
        IF(is_visit_completed, ts_booking_utc, NULL) AS ts_visit_completed
    FROM 
        datalake_booking.booking
    WHERE
        visit_intent = "SALE"
        AND type = 'Visita'
),
first_booking AS (
    SELECT
        id_user,
        id_attendant,
        user_sale_booking_creator AS first_booking_creator_5a,
        ts_created AS ts_first_booking_created
    FROM
        bookings_reference_table
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_created ASC) = 1
),
last_booking AS (
    SELECT
        id_user,
        id_attendant,
        user_sale_booking_creator AS last_booking_creator_5a,
        ts_created AS ts_last_booking_created
    FROM
        bookings_reference_table
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_created DESC) = 1
),
responsible_lead AS (
    SELECT
        l.id_user,
        l.id_visitor,
        FIRST_VALUE(r.ts_assigned) OVER(
            PARTITION BY
                COALESCE(l.id_user, l.id_visitor)
            ORDER BY
                r.ts_created
        ) ts_first_assignment
    FROM
        datalake_hub_services_clean.responsible AS r
    JOIN
        leads_reference_table AS l
            USING(id_lead)
    QUALIFY
        ROW_NUMBER() OVER(
            PARTITION BY
                COALESCE(l.id_user, l.id_visitor)
            ORDER BY
                r.ts_created DESC,
                ts_unassigned DESC
        ) = 1
),
has_booking AS (
    SELECT
        rl.id_user,
        COALESCE(fb.ts_first_booking_created < rl.ts_first_assignment, FALSE) AS has_booking_before_secretariat_contact
    FROM
        responsible_lead AS rl
    LEFT JOIN
        first_booking AS fb
            ON rl.id_user = fb.id_user
),
total_bookings AS (
    SELECT
        id_user,
        COUNT_IF(user_sale_booking_creator = 'Secretaria') AS total_bookings_created_by_secretariat,
        COUNT(*) AS total_bookings_created,
        COUNT_IF(status = 'Cancelado') AS total_bookings_canceled,
        COUNT_IF(is_visit_completed) AS total_visits_completed,
        COUNT_IF(is_visit_completed AND user_sale_booking_creator = 'Secretaria') AS total_visits_completed_by_secretariat
    FROM
        bookings_reference_table
    GROUP BY 1
),
sales_reference_table AS (
    SELECT
        id_buyer,
        id_offer,
        id_booking,
        ts_offer_submitted,
        DATE(ts_offer_accepted) AS dt_offer_accepted,
        DATE(ts_sale_agreement_signed) AS dt_sale_agreement_signed
    FROM
        datalake_sale_offer.sale_offer
),
total_offers AS (
    SELECT
        tsr.id_buyer AS id_user,
        COUNT(*) AS total_offers_submitted,
        COUNT(dt_sale_agreement_signed) AS total_sale_agreements_signed
    FROM
        sales_reference_table tsr
    GROUP BY 1
),
NCPsec AS (
    SELECT
        fl.id_user,
        fl.id_visitor,
        CASE
            WHEN NOT hb.has_booking_before_secretariat_contact THEN hu.name
        END AS secretariat_name,
        CASE
            WHEN NOT hb.has_booking_before_secretariat_contact THEN hu.email
        END AS secretariat_email,
        CASE
            WHEN NOT hb.has_booking_before_secretariat_contact THEN hu.allocation
        END AS allocation,
        CASE
            WHEN NOT hb.has_booking_before_secretariat_contact THEN hu.segment
        END AS segment
    FROM
        first_lead AS fl
    LEFT JOIN
        responsible_reference_table AS rr
            ON fl.id_lead = rr.id_lead
    LEFT JOIN
        hs_users_reference_table AS hu
            ON rr.id_user_hub_services = hu.id_user_hub_services
    LEFT JOIN
        has_booking AS hb
            ON fl.id_user = hb.id_user
),
NCP AS (
    SELECT
        fl.id_user,
        fl.id_visitor,
        hu.name AS secretariat_name,
        hu.email AS secretariat_email,
        hu.allocation AS allocation,
        hu.segment AS segment
    FROM
        first_lead AS fl
    LEFT JOIN
        responsible_reference_table AS rr
            ON fl.id_lead = rr.id_lead
    LEFT JOIN
        hs_users_reference_table AS hu
            ON rr.id_user_hub_services = hu.id_user_hub_services
),
NBPsec AS (
    SELECT
        fb.id_user,
        CASE
            WHEN fb.first_booking_creator_5a = 'Secretaria' THEN hu.name
        END AS secretariat_name,
        CASE
            WHEN fb.first_booking_creator_5a = 'Secretaria' THEN hu.email
        END AS secretariat_email,
        CASE
            WHEN fb.first_booking_creator_5a = 'Secretaria' THEN hu.allocation
        END AS allocation,
        CASE
            WHEN fb.first_booking_creator_5a = 'Secretaria' THEN hu.segment
        END AS segment
    FROM
        first_booking AS fb
    LEFT JOIN
        hs_users_reference_table AS hu
            ON fb.id_attendant = hu.id_user
),
NBP AS (
    SELECT
        fl.id_user,
        CASE
            WHEN hb.has_booking_before_secretariat_contact THEN hs_primeiro_associado.name
            ELSE NBPsec.secretariat_name
        END AS secretariat_name,
        CASE
            WHEN hb.has_booking_before_secretariat_contact THEN hs_primeiro_associado.email
            ELSE NBPsec.secretariat_email
        END AS secretariat_email,
        CASE
            WHEN hb.has_booking_before_secretariat_contact THEN hs_primeiro_associado.allocation
            ELSE NBPsec.allocation
        END AS allocation,
        CASE
            WHEN hb.has_booking_before_secretariat_contact THEN hs_primeiro_associado.segment
            ELSE NBPsec.segment
        END AS segment
    FROM
        first_lead AS fl
    LEFT JOIN
        responsible_reference_table AS rr
            ON fl.id_lead = rr.id_lead
    LEFT JOIN
        hs_users_reference_table AS hs_primeiro_associado
            ON rr.id_user_hub_services = hs_primeiro_associado.id_user_hub_services
    LEFT JOIN
        has_booking AS hb
            ON fl.id_user = hb.id_user
    LEFT JOIN
        NBPsec
            ON fl.id_user = NBPsec.id_user
),
first_visit_completed AS (
    SELECT
        id_user,
        id_booking,
        id_attendant,
        user_sale_booking_creator,
        ts_visit_completed AS ts_first_visit_completed,
        is_visit_completed
    FROM
        bookings_reference_table AS tbr
    WHERE
        is_visit_completed
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_visit_completed ASC) = 1
),
last_visit_completed AS (
    SELECT
        id_user,
        id_booking,
        ts_visit_completed AS ts_last_visit_completed
    FROM
        bookings_reference_table AS tbr
    WHERE
        is_visit_completed
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_user ORDER BY ts_visit_completed DESC) = 1
),
VC AS (
    SELECT
        fv.id_user,
        ts_first_visit_completed AS ts_first_visit_completed,
        ts_last_visit_completed AS ts_last_visit_completed,
        hu.name AS secretariat_name,
        hu.email AS secretariat_email,
        hu.allocation AS allocation,
        hu.segment AS segment
    FROM
        first_visit_completed AS fv
    LEFT JOIN
        hs_users_reference_table AS hu
            ON fv.id_attendant = hu.id_user
    INNER JOIN
        last_visit_completed AS lv
            ON fv.id_user = lv.id_user
),
first_offer_sub AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        ts_offer_submitted AS ts_first_offer_submitted
    FROM
        sales_reference_table
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY ts_offer_submitted ASC) = 1
),
first_offer_acc AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        dt_offer_accepted AS ts_first_offer_accepted
    FROM
        sales_reference_table
    WHERE
        dt_offer_accepted IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY dt_offer_accepted ASC) = 1
),
first_offer_agr AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        dt_sale_agreement_signed AS ts_first_sale_agreement_signed
    FROM
        sales_reference_table
    WHERE
        dt_sale_agreement_signed IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY dt_sale_agreement_signed ASC) = 1
),
last_offer_sub AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        ts_offer_submitted AS ts_last_offer_submitted
    FROM
        sales_reference_table
    QUALIFY
          ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY ts_offer_submitted DESC) = 1
),
last_offer_acc AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        dt_offer_accepted AS ts_last_offer_accepted
    FROM
        sales_reference_table
    WHERE
        dt_offer_accepted IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY dt_offer_accepted DESC) = 1
),
last_offer_agr AS (
    SELECT
        id_buyer AS id_user,
        id_booking,
        dt_sale_agreement_signed AS ts_last_sale_agreement_signed
    FROM
        sales_reference_table
    WHERE
        dt_sale_agreement_signed IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_buyer ORDER BY dt_sale_agreement_signed DESC) = 1
),
OS AS (
    SELECT
        fo.id_user,
        fo.ts_first_offer_submitted,
        lo.ts_last_offer_submitted,
        hu.name AS secretariat_name,
        hu.email AS secretariat_email,
        hu.allocation AS allocation,
        hu.segment AS segment
    FROM
        first_offer_sub AS fo
    INNER JOIN
        last_offer_sub AS lo
            ON fo.id_user = lo.id_user
    INNER JOIN
        bookings_reference_table AS tb
            ON fo.id_booking = tb.id_booking
    LEFT JOIN
        hs_users_reference_table AS hu
            ON tb.id_attendant = hu.id_user
    LEFT JOIN
        last_visit_completed AS lv
            ON hu.id_user = lv.id_user
    WHERE
        tb.is_visit_completed
),
OA AS(
    SELECT
        fo.id_user,
        fo.ts_first_offer_accepted,
        lo.ts_last_offer_accepted,
        hu.name AS secretariat_name,
        hu.email AS secretariat_email,
        hu.allocation AS allocation,
        hu.segment AS segment
    FROM
        first_offer_acc AS fo
    INNER JOIN
        last_offer_acc AS lo
            ON fo.id_user = lo.id_user
    INNER JOIN
        bookings_reference_table AS tb
            ON fo.id_booking = tb.id_booking
    LEFT JOIN
        hs_users_reference_table AS hu
            ON tb.id_attendant = hu.id_user
    LEFT JOIN
        last_visit_completed AS lv
            ON hu.id_user = lv.id_user
    WHERE
        tb.is_visit_completed
),
CCV_FIRST AS (
    SELECT
          fo.id_user,
          fo.ts_first_sale_agreement_signed,
          hu.name AS secretariat_name,
          hu.email AS secretariat_email,
          hu.allocation AS allocation,
          hu.segment AS segment
    FROM
        first_offer_agr AS fo
    INNER JOIN
        bookings_reference_table AS tb
            ON fo.id_booking = tb.id_booking
    LEFT JOIN
        hs_users_reference_table AS hu
              ON tb.id_attendant = hu.id_user
    LEFT JOIN
        last_visit_completed lv
            ON hu.id_user = lv.id_user
    WHERE
        tb.is_visit_completed
),
CCV_LAST AS (
    SELECT
        lo.id_user,
        hu.id_user AS id_secretariat,
        lo.ts_last_sale_agreement_signed,
        hu.name AS secretariat_name,
        hu.email AS secretariat_email,
        hu.allocation AS allocation,
        hu.segment AS segment
    FROM
        last_offer_agr AS lo
    INNER JOIN
        bookings_reference_table AS tb
            ON lo.id_booking = tb.id_booking
    LEFT JOIN
        hs_users_reference_table AS hu
            ON tb.id_attendant = hu.id_user
    LEFT JOIN
        last_visit_completed AS lv
            ON hu.id_user = lv.id_user
    WHERE
        tb.is_visit_completed
),
last_secretariat AS (
    SELECT
        ll.id_user,
        ll.id_visitor,
        hu.name AS last_secretariat_name,
        hu.allocation AS last_allocation,
        hu.email AS last_secretariat_email,
        hu.segment AS segment
    FROM
        last_lead AS ll
    JOIN
        hs_users_reference_table AS hu
            ON ll.id_user_hub_services_responsible = hu.id_user_hub_services
)
SELECT
    COALESCE(tur.id_user, -1) AS id_user,
    COALESCE(tur.id_visitor, -1) AS id_visitor,
    COALESCE(ll.id_house, -1) AS id_house_last_intent,
    hr.region,
    fl.first_contact_prospect_origin,
    fb.first_booking_creator_5a,
    NCP.secretariat_name AS name_secretariat_NCP,
    NCP.secretariat_email AS email_secretariat_NCP,
    NCP.allocation AS allocation_NCP,
    NCP.segment AS segment_NCP,
    NCPsec.secretariat_name AS name_secretariat_NCPsec,
    NCPsec.secretariat_email AS email_secretariat_NCPsec,
    NCPsec.allocation AS allocation_NCPsec,
    NCPsec.segment AS segment_NCPsec,
    NBP.secretariat_name AS name_secretariat_NBP,
    NBP.secretariat_email AS email_secretariat_NBP,
    NBP.allocation AS allocation_NBP,
    NBP.segment AS segment_NBP,
    NBPsec.secretariat_name AS name_secretariat_NBPsec,
    NBPsec.secretariat_email AS email_secretariat_NBPsec,
    NBPsec.allocation AS allocation_NBPsec,
    NBPsec.segment AS segment_NBPsec,
    VC.secretariat_name AS name_secretariat_VC,
    VC.secretariat_email AS email_secretariat_VC,
    VC.allocation AS allocation_VC,
    VC.segment AS segment_VC,
    OS.secretariat_name AS name_secretariat_OS,
    OS.secretariat_email AS email_secretariat_OS,
    OS.allocation AS allocation_OS,
    OS.segment AS segment_OS,
    OA.secretariat_name AS name_secretariat_OA,
    OA.secretariat_email AS email_secretariat_OA,
    OA.allocation AS allocation_OA,
    OA.segment AS segment_OA,
    CCV_FIRST.secretariat_name AS name_secretariat_first_CCV,
    CCV_FIRST.secretariat_email AS email_secretariat_first_CCV,
    CCV_FIRST.allocation AS allocation_first_CCV,
    CCV_FIRST.segment AS segment_first_CCV,
    CCV_LAST.secretariat_name AS name_secretariat_last_CCV,
    CCV_LAST.secretariat_email AS email_secretariat_last_CCV,
    CCV_LAST.allocation AS allocation_last_CCV,
    CCV_LAST.segment AS segment_last_CCV,
    tur.email AS email_client,
    tur.phone_number AS phone_client,
    ls.last_secretariat_name AS last_secretariat_name,
    ls.last_allocation AS last_allocation,
    ls.last_secretariat_email AS last_secretariat_email,
    ls.segment AS last_segment,
    CASE
          WHEN CCV_FIRST.ts_first_sale_agreement_signed IS NOT NULL THEN 'sale_agreement_signed'
          WHEN OA.ts_first_offer_accepted IS NOT NULL THEN 'offer_accepted'
          WHEN OS.ts_first_offer_submitted IS NOT NULL THEN 'offer_submitted'
          WHEN VC.ts_first_visit_completed IS NOT NULL THEN 'visit_completed'
          WHEN fb.ts_first_booking_created IS NOT NULL THEN 'booking_created'
          ELSE 'contact_prospect'
    END AS further_funnel_step,
    COALESCE(tb.total_bookings_created_by_secretariat, 0) AS total_bookings_created_by_secretariat,
    COALESCE(tb.total_bookings_created, 0) AS total_bookings_created,
    COALESCE(tb.total_bookings_canceled, 0) AS total_bookings_canceled,
    COALESCE(tb.total_visits_completed, 0) AS total_visits_completed,
    COALESCE(tb.total_visits_completed_by_secretariat, 0) AS total_visits_completed_by_secretariat,
    COALESCE(total_offers_submitted, 0) AS total_offers_submitted,
    COALESCE(total_sale_agreements_signed, 0) AS total_sale_agreements_signed,
    COALESCE(hb.has_booking_before_secretariat_contact, FALSE) AS has_booking_before_secretariat_contact,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(fl.ts_first_contact_prospect, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_contact_prospect_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(ll.ts_last_contact_prospect, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_contact_prospect_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(fb.ts_first_booking_created, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_booking_created_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(lb.ts_last_booking_created, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_booking_created_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(VC.ts_first_visit_completed, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_visit_completed_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(VC.ts_last_visit_completed, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_visit_completed_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(OS.ts_first_offer_submitted, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_offer_submitted_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(OS.ts_last_offer_submitted, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_offer_submitted_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(OA.ts_first_offer_accepted, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_offer_accepted_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(OA.ts_last_offer_accepted, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_offer_accepted_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(CCV_FIRST.ts_first_sale_agreement_signed, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_first_sale_agreement_signed_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(CCV_LAST.ts_last_sale_agreement_signed, 'America/Sao_Paulo'),
        'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_sale_agreement_signed_local_tz,
    DATE_FORMAT(
        FROM_UTC_TIMESTAMP(
            GREATEST(
                fl.ts_first_contact_prospect,
                ll.ts_last_contact_prospect,
                fb.ts_first_booking_created,
                lb.ts_last_booking_created,
                VC.ts_first_visit_completed,
                VC.ts_last_visit_completed,
                OS.ts_first_offer_submitted,
                OS.ts_last_offer_submitted,
                OA.ts_first_offer_accepted,
                OA.ts_last_offer_accepted,
                CCV_FIRST.ts_first_sale_agreement_signed,
                CCV_LAST.ts_last_sale_agreement_signed
            ),
            'America/Sao_Paulo'
        ),
        'yyyy-MM-dd HH:mm:ss'
    ) AS dt_last_local_tz
FROM
    users_reference_table AS tur
JOIN
    responsible_lead AS rl -- Only get users that have one active responsible
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(rl.id_user, rl.id_visitor)
LEFT JOIN
    house_region AS hr
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(hr.id_user, hr.id_visitor)
LEFT JOIN
    first_lead AS fl
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(fl.id_user, fl.id_visitor)
LEFT JOIN
    first_booking AS fb
        ON tur.id_user = fb.id_user
LEFT JOIN
    has_booking AS hb
        ON tur.id_user = hb.id_user
LEFT JOIN
    total_bookings AS tb
        ON tur.id_user = tb.id_user
LEFT JOIN
    total_offers AS tto
        ON tur.id_user = tto.id_user
LEFT JOIN
    last_lead AS ll
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(ll.id_user, ll.id_visitor)
LEFT JOIN
    NCP
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(NCP.id_user, NCP.id_visitor)
LEFT JOIN
    NCPsec
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(NCPsec.id_user, NCPsec.id_visitor)
LEFT JOIN
    last_booking AS lb
        ON tur.id_user = lb.id_user
LEFT JOIN
    NBP
        ON tur.id_user = NBP.id_user
LEFT JOIN
    NBPsec
        ON tur.id_user = NBPsec.id_user
LEFT JOIN
    VC
        ON tur.id_user = VC.id_user
LEFT JOIN
    OA
        ON tur.id_user = OA.id_user
LEFT JOIN
    OS
        ON tur.id_user = OS.id_user
LEFT JOIN
    CCV_FIRST
        ON tur.id_user = CCV_FIRST.id_user
LEFT JOIN
    CCV_LAST
        ON tur.id_user = CCV_LAST.id_user
LEFT JOIN
    last_secretariat AS ls
        ON COALESCE(tur.id_user, tur.id_visitor) = COALESCE(ls.id_user, ls.id_visitor)
WHERE
    ncp.allocation IS DISTINCT FROM '3P'
