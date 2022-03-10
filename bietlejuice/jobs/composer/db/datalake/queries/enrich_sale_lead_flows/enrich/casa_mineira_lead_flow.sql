WITH all_contacts AS (
    WITH aux AS (
        SELECT
            ct.id_client,
            LOWER(COALESCE(ct.email, c.email)) AS email,
            COALESCE(ct.phone_number, c.phone_number) AS phone_number,
            ct.contact_type,
            ct.ts_created
        FROM
            datalake_casa_mineira_crm_clean.contact AS ct
        JOIN
            datalake_casa_mineira_crm_clean.client AS c
                ON c.id = ct.id_client
        UNION ALL
        SELECT
            ct.id_client,
            LOWER(COALESCE(c.email, ct.email)) AS email,
            COALESCE(c.phone_number, ct.phone_number) AS phone_number,
            ct.contact_type,
            c.ts_created
        FROM
            datalake_casa_mineira_crm_clean.contact AS ct
        JOIN
            datalake_casa_mineira_crm_clean.client AS c
                ON c.id = ct.id_client
    )
    SELECT DISTINCT
        id_client,
        email,
        CASE
            WHEN RIGHT(phone_number, 7) 
                IN (
                    '1111111',
                    '9999999',
                    '0000000',
                    '1212121',
                    '3456789',
                    '1234567',
                    '2222222',
                    '3333333',
                    '4444444',
                    '5555555',
                    '6666666',
                    '7777777',
                    '8888888',
                    '9999991'
                )
                THEN NULL
            ELSE '+55'||phone_number
        END AS phone_number
    FROM
        aux
    WHERE
        DATE(ts_created) >= '2020-01-01'
        AND contact_type != 'cancelamento'
),
unique_users_list_ids AS (
    SELECT
        ac.id_client AS id_secretariat_client,
        COLLECT_LIST(DISTINCT ac.email) AS list_emails,
        COLLECT_LIST(DISTINCT ac.phone_number) AS list_phone_numbers
    FROM
        all_contacts AS ac
    GROUP BY
        1
),
secretariat_contact AS (
    SELECT
        uu.id_secretariat_client,
        CAST(h.id_house_quintoandar AS BIGINT) AS id_house_5a,
        c.id_house AS id_house_cm,
        qah.id_region AS id_region_secretariat_contact,
        cth.city_name AS city_secretariat_contact,
        CASE
            WHEN oc.origin_contact_name IN ('Combo de Eventos Hub', 'Quinto Andar Lite - Combo de eventos') THEN 'Combo de Eventos'
            WHEN oc.origin_contact_name IN ('Quinto Andar - Placas') THEN 'Placas'
            WHEN oc.origin_contact_name IN ('Quinto Andar - Traz quem compra') THEN 'TQC'
            WHEN oc.origin_contact_name IN ('Quinto Andar Classificados Hub','Quinto Andar Classificados Lite') THEN 'Classificados'
            WHEN oc.origin_contact_name IN ('Quinto Andar Lite', 'QuintoAndar') THEN 'QuintoAndar'
            ELSE 'Other'
        END AS secretariat_contact_origin,
        mc.media_contact_name AS secretariat_contact_media,
        'BH' AS business_unit,
        ROW_NUMBER() OVER (
            PARTITION BY 
                uu.id_secretariat_client
            ORDER BY
                c.ts_created
        ) AS rw_asc,
        ROW_NUMBER() OVER (
            PARTITION BY 
                uu.id_secretariat_client
            ORDER BY
                c.ts_created
            DESC
        ) AS rw_desc,
        TO_UTC_TIMESTAMP(c.ts_created, 'America/Sao_Paulo') AS ts_secretariat_contact
    FROM
        unique_users_list_ids AS uu
    JOIN 
        datalake_casa_mineira_crm_clean.contact AS c
            ON c.id_client = uu.id_secretariat_client
    LEFT JOIN
        datalake_casa_mineira_crm_clean.origin_contact AS oc
            ON oc.id = c.id_origin
    LEFT JOIN
        datalake_casa_mineira_crm_clean.media_contact AS mc
            ON mc.id = c.id_media
    LEFT JOIN
        datalake_casa_mineira_crm_clean.house AS h
            ON h.id = c.id_house
    LEFT JOIN
        datalake_casa_mineira_crm_clean.neighborhood AS nh
            ON nh.id = h.id_neighborhood
    LEFT JOIN
        datalake_casa_mineira_crm_clean.city AS cth
            ON cth.id = nh.id_city
    LEFT JOIN
        datalake_ebdb_clean.house AS qah
            ON qah.id = h.id_house_quintoandar
),
first_secretariat_contact AS (
    SELECT *
    FROM
        secretariat_contact
    WHERE
        rw_asc = 1
),
last_secretariat_contact AS (
    SELECT *
    FROM
        secretariat_contact
    WHERE
        rw_desc = 1
),
first_combo_contact AS (
    SELECT
        id_secretariat_client,
        MIN(ts_secretariat_contact) AS ts_first_combo_event_contact_prospect
    FROM
        secretariat_contact
    WHERE
        secretariat_contact_origin = 'Combo de Eventos'
    GROUP BY
        id_secretariat_client
),
last_combo_contact AS (
    SELECT
        id_secretariat_client,
        MAX(ts_secretariat_contact) AS ts_last_combo_event_contact_prospect
    FROM
        secretariat_contact
    WHERE
        secretariat_contact_origin = 'Combo de Eventos'
    GROUP BY
        id_secretariat_client
),
booking AS (
    SELECT
        uu.id_secretariat_client,
        v.id_house AS id_house_cm,
        CAST(h.id_house_quintoandar AS BIGINT) AS id_house_5a,
        qah.id_region AS id_region_booking,
        cth.city_name AS city_booking,
        'BH' AS business_unit,
        validation_type,
        ROW_NUMBER() OVER (
            PARTITION BY
                uu.id_secretariat_client
            ORDER BY
                v.ts_created
        ) AS rw_asc,
        ROW_NUMBER() OVER (
            PARTITION BY
                uu.id_secretariat_client
            ORDER BY
                v.ts_created
            DESC
        ) AS rw_desc,
        TO_UTC_TIMESTAMP(v.ts_created, 'America/Sao_Paulo') AS ts_booking_created
    FROM
        unique_users_list_ids AS uu
    JOIN
        datalake_casa_mineira_crm_clean.visit AS v
            ON v.id_client = uu.id_secretariat_client
    JOIN
        datalake_casa_mineira_crm_clean.house AS h
            ON h.id = v.id_house
    LEFT JOIN
        datalake_casa_mineira_crm_clean.neighborhood AS nh
            ON nh.id = h.id_neighborhood
    LEFT JOIN
        datalake_casa_mineira_crm_clean.city AS cth
            ON cth.id = nh.id_city
    LEFT JOIN
        datalake_ebdb_clean.house AS qah
            ON qah.id = h.id_house_quintoandar
),
first_booking AS (
    SELECT *
    FROM
        booking
    WHERE
        rw_asc = 1
),
last_booking AS (
    SELECT *
    FROM
        booking
    WHERE
        rw_desc = 1
),
booking_statistics AS (
    SELECT
        id_secretariat_client,
        COUNT(*) AS total_bookings_created,
        COUNT(
            CASE
                WHEN validation_type='cancelado' THEN 1
            END
        ) AS total_bookings_canceled
    FROM
        booking
    GROUP BY
        id_secretariat_client
),
visit AS (
    SELECT
        uu.id_secretariat_client,
        ROW_NUMBER() OVER (
            PARTITION BY
                uu.id_secretariat_client
            ORDER BY
                v.ts_visited
        ) AS rw_asc,
        ROW_NUMBER() OVER (
            PARTITION BY
                uu.id_secretariat_client
            ORDER BY
                v.ts_visited 
            DESC
        ) AS rw_desc,
        TO_UTC_TIMESTAMP(v.ts_visited, 'America/Sao_Paulo') AS ts_visit_completed
    FROM
        unique_users_list_ids AS uu
    JOIN
        datalake_casa_mineira_crm_clean.visit AS v
            ON v.id_client = uu.id_secretariat_client
    JOIN
        datalake_casa_mineira_crm_clean.house AS h
            ON h.id = v.id_house
    WHERE
        v.validation_type ='confirmado'
),
visit_statistics AS (
    SELECT
        id_secretariat_client,
        COUNT(*) AS total_visits_completed
    FROM
        visit
    GROUP BY
        id_secretariat_client
),
first_visit AS (
    SELECT *
    FROM
        visit
    WHERE
        rw_asc = 1
),
last_visit AS (
    SELECT *
    FROM
        visit
    WHERE
        rw_desc = 1
), 
offers_and_ccvs AS (
    SELECT
        id_secretariat_client,
        h.id AS id_house_cm,
        CAST(id_house_quintoandar AS BIGINT) AS id_house_5a,
        CAST(s.id AS STRING) AS id_offer,
        qah.id_region AS id_region_offer,
        'BH' AS offer_flow,
        'BH' AS business_unit,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_secretariat_client 
            ORDER BY
                s.ts_created
        ) AS rw_offer_asc,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_secretariat_client
            ORDER BY
                s.ts_sold
        ) AS rw_ccv_asc,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_secretariat_client
            ORDER BY
                s.ts_created
            DESC
        ) AS rw_offer_desc,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_secretariat_client
            ORDER BY
                s.ts_sold
            DESC
        ) AS rw_ccv_desc,
        s.ts_created AS ts_offer_submitted,
        s.ts_sold AS ts_sale_agreement_signed
    FROM
        unique_users_list_ids AS uu
    JOIN
        datalake_casa_mineira_crm_clean.sale AS s
            ON uu.id_secretariat_client = s.id_client
    LEFT JOIN
        datalake_casa_mineira_crm_clean.house AS h
            ON s.id_house = h.id
    LEFT JOIN
        datalake_ebdb_clean.house AS qah
            ON qah.id = h.id_house_quintoandar
    WHERE
        id_client IS NOT NULL
),
offers_and_ccvs_statistics AS (
    SELECT
        id_secretariat_client,
        COUNT(*) AS total_offers_submitted,
        COUNT(
            CASE
                WHEN ts_sale_agreement_signed IS NOT NULL THEN 1
            END
        ) AS total_sale_agreements_signed
    FROM
        offers_and_ccvs
    GROUP BY
        id_secretariat_client
),
first_offer AS (
    SELECT *
    FROM
        offers_and_ccvs
    WHERE
        rw_offer_asc = 1
),
last_offer AS (
    SELECT *
    FROM
        offers_and_ccvs
    WHERE
        rw_offer_desc = 1
),
first_ccv AS (
    SELECT *
    FROM
        offers_and_ccvs
    WHERE
        rw_ccv_asc = 1
        AND ts_sale_agreement_signed IS NOT NULL
),
last_ccv AS (
    SELECT *
    FROM
        offers_and_ccvs
    WHERE
        rw_ccv_desc = 1
        AND ts_sale_agreement_signed IS NOT NULL
)
SELECT
    uu.id_secretariat_client,
    COALESCE(fsc.id_region_secretariat_contact,-1) AS id_first_region_contact_prospect,
    COALESCE(lsc.id_region_secretariat_contact,-1) AS id_last_region_contact_prospect,
    COALESCE(fb.id_region_booking,-1) AS id_first_region_booking,
    COALESCE(lb.id_region_booking,-1) AS id_last_region_booking,
    COALESCE(fo.id_region_offer, -1) AS id_first_region_offer,
    COALESCE(lo.id_region_offer, -1) AS id_last_region_offer,
    COALESCE(fsc.id_house_5a, -1) AS id_first_house_5a_secretariat_contact,
    COALESCE(fsc.id_house_cm, -1) AS id_first_house_cm_secretariat_contact,
    COALESCE(lsc.id_house_5a, -1) AS id_last_house_5a_secretariat_contact,
    COALESCE(lsc.id_house_cm, -1) AS id_last_house_cm_secretariat_contact,
    COALESCE(fb.id_house_5a, -1) AS id_first_house_5a_booking,
    COALESCE(fb.id_house_cm, -1) AS id_first_house_cm_booking,
    COALESCE(lb.id_house_5a, -1) AS id_last_house_5a_booking,
    COALESCE(lb.id_house_cm, -1) AS id_last_house_cm_booking,
    COALESCE(fo.id_house_cm, -1) AS id_first_house_cm_offer,
    COALESCE(lo.id_house_cm, -1) AS id_last_house_cm_offer,
    COALESCE(fc.id_house_cm, -1) AS id_first_house_cm_sale_agreement,
    COALESCE(lc.id_house_cm, -1) AS id_last_house_cm_sale_agreement,
    uu.list_emails,
    uu.list_phone_numbers,
    CASE
        WHEN GREATEST(fsc.ts_secretariat_contact,
                      fc.ts_sale_agreement_signed,
                      fo.ts_offer_submitted,
                      fv.ts_visit_completed,
                      fb.ts_booking_created) = fsc.ts_secretariat_contact
            THEN 'lead_submission'
        WHEN GREATEST(fsc.ts_secretariat_contact,
                      fc.ts_sale_agreement_signed,
                      fo.ts_offer_submitted,
                      fv.ts_visit_completed,
                      fb.ts_booking_created) = fc.ts_sale_agreement_signed
            THEN 'sale_agreement_signed'
        WHEN GREATEST(fsc.ts_secretariat_contact,
                      fc.ts_sale_agreement_signed, 
                      fo.ts_offer_submitted,
                      fv.ts_visit_completed, 
                      fb.ts_booking_created) = fo.ts_offer_submitted
            THEN 'offer_submitted'
        WHEN GREATEST(fsc.ts_secretariat_contact,
                      fc.ts_sale_agreement_signed, 
                      fo.ts_offer_submitted,
                      fv.ts_visit_completed, 
                      fb.ts_booking_created) = fv.ts_visit_completed
            THEN 'visit_completed'
        WHEN GREATEST(fsc.ts_secretariat_contact,
                      fc.ts_sale_agreement_signed, 
                      fo.ts_offer_submitted,
                      fv.ts_visit_completed, 
                      fb.ts_booking_created) = fb.ts_booking_created
            THEN 'booking_created'
    END AS further_funnel_step,
    fsc.city_secretariat_contact AS first_city_contact_prospect,
    lsc.city_secretariat_contact AS last_city_contact_prospect,
    fsc.secretariat_contact_origin AS first_secretariat_contact_origin,
    lsc.secretariat_contact_origin AS last_secretariat_contact_origin,
    fsc.secretariat_contact_media AS first_secretariat_contact_media,
    lsc.secretariat_contact_media AS last_secretariat_contact_media,
    fb.city_booking AS first_city_booking,
    lb.city_booking AS last_city_booking,
    fo.offer_flow AS first_offer_flow,
    lo.offer_flow AS last_offer_flow,
    fc.offer_flow AS first_ccv_flow,
    lc.offer_flow AS last_ccv_flow,
    fsc.business_unit AS first_business_unit_region_intent_lead,
    lsc.business_unit AS last_business_unit_region_intent_lead,
    fb.business_unit AS first_business_unit_region_new_buyer_prospect,
    fo.business_unit AS first_offer_business_unit,
    lo.business_unit AS last_offer_business_unit,
    fc.business_unit AS first_ccv_business_unit,
    lc.business_unit AS last_ccv_business_unit,
    COALESCE(bs.total_bookings_created, 0) > 0 AS has_first_booking,
    fsc.id_secretariat_client IS NOT NULL AS has_secretariat_contact_created,
    COALESCE(bs.total_bookings_created, 0) AS total_bookings_created,
    COALESCE(bs.total_bookings_canceled, 0) AS total_bookings_canceled,
    COALESCE(vs.total_visits_completed, 0) AS total_visits_completed,
    COALESCE(ocs.total_offers_submitted, 0) AS total_offers_submitted,
    COALESCE(ocs.total_sale_agreements_signed, 0) AS total_sale_agreements_signed,
    fsc.ts_secretariat_contact AS ts_first_contact_prospect,
    lsc.ts_secretariat_contact AS ts_last_contact_prospect,
    fcc.ts_first_combo_event_contact_prospect,
    lcc.ts_last_combo_event_contact_prospect,
    fb.ts_booking_created AS ts_first_booking_created,
    lb.ts_booking_created AS ts_last_booking_created,
    fv.ts_visit_completed AS ts_first_visit_completed,
    lv.ts_visit_completed AS ts_last_visit_completed,
    fo.ts_offer_submitted AS ts_first_offer_submitted,
    lo.ts_offer_submitted AS ts_last_offer_submitted,
    fc.ts_sale_agreement_signed AS ts_first_sale_agreement_signed,
    lc.ts_sale_agreement_signed AS ts_last_sale_agreement_signed
FROM
    unique_users_list_ids AS uu
LEFT JOIN
    first_secretariat_contact AS fsc
        ON fsc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    first_combo_contact AS fcc
        ON fcc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    first_booking AS fb
        ON fb.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    first_visit AS fv
        ON fv.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    first_offer AS fo
        ON fo.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    first_ccv AS fc
        ON fc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_secretariat_contact AS lsc
        ON lsc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_combo_contact AS lcc
        ON lcc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_booking AS lb
        ON lb.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_visit AS lv
        ON lv.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_offer AS lo
        ON lo.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    last_ccv AS lc
        ON lc.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    booking_statistics AS bs
        ON bs.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    visit_statistics AS vs
        ON vs.id_secretariat_client = uu.id_secretariat_client
LEFT JOIN
    offers_and_ccvs_statistics AS ocs
        ON ocs.id_secretariat_client = uu.id_secretariat_client