WITH all_users_5a AS (
    WITH user_aud AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY rev DESC) AS rw
        FROM datalake_ebdb_clean_prod.user_aud -- some users can be deleted, so we have to search in user_aud
        )
    SELECT
        id_user,
        LOWER(email) AS email,
        CASE
            WHEN RIGHT(main_phone,7) IN ('1111111','9999999','0000000','1212121','3456789','1234567','2222222','3333333','4444444','5555555','6666666','7777777','8888888','9999991')
                THEN NULL
            ELSE main_phone
        END AS phone_number
    FROM user_aud
    WHERE rw = 1
)
, all_contacts_casamineira AS (
    WITH aux AS (
        SELECT
            ct.id_client,
            LOWER(COALESCE(ct.email, c.email)) AS email,
            CASE
                WHEN RIGHT(COALESCE(ct.phone_number, c.phone_number),7) IN ('1111111','9999999','0000000','1212121','3456789','1234567','2222222','3333333','4444444','5555555','6666666','7777777','8888888','9999991')
                    THEN NULL
                ELSE '+55'||COALESCE(ct.phone_number, c.phone_number)
            END AS phone_number
        FROM datalake_casa_mineira_crm_clean_prod.contact ct
        JOIN datalake_casa_mineira_crm_clean_prod.client c
            ON c.id = ct.id_client
        WHERE
            ct.ts_created::date >= '2021-04-26' -- start date of hub secretariat in 5A
            AND ct.contact_type != 'cancelamento'
    UNION ALL
        SELECT
            ct.id_client,
            LOWER(COALESCE(c.email, ct.email)) AS email,
            CASE
                WHEN RIGHT(COALESCE(c.phone_number, ct.phone_number),7) IN ('1111111','9999999','0000000','1212121','3456789','1234567','2222222','3333333','4444444','5555555','6666666','7777777','8888888','9999991')
                    THEN NULL
                ELSE '+55'||COALESCE(c.phone_number,ct.phone_number)
            END AS phone_number
        FROM datalake_casa_mineira_crm_clean_prod.contact ct
        JOIN datalake_casa_mineira_crm_clean_prod.client c
            ON c.id = ct.id_client
        WHERE
            c.ts_created::date >= '2021-04-26' -- start date of hub secretariat in 5A
            AND ct.contact_type != 'cancelamento'
        )
    SELECT
        DISTINCT
        id_client,
        email,
        phone_number
    FROM aux
)
, match_5a_cm AS (
    WITH match_email AS (
        SELECT
            u.id_user,
            c.id_client
        FROM all_users_5a u
        JOIN all_contacts_casamineira c
            ON u.email = c.email
    )
    , match_phone AS (
        SELECT
            u.id_user,
            c.id_client
        FROM all_users_5a u
        JOIN all_contacts_casamineira c
            ON u.phone_number = c.phone_number
        LEFT JOIN match_email me
            ON me.id_user = u.id_user
            OR me.id_client = c.id_client
        WHERE me.id_user IS NULL AND me.id_client IS NULL
    )
    SELECT
        me.id_user,
        me.id_client
    FROM match_email me
UNION ALL
    SELECT
        mp.id_user,
        mp.id_client
    FROM match_phone mp
)
, unique_users_and_clients AS (
    SELECT
        COALESCE(m.id_user, u.id_user) AS id_user,
        COALESCE(m.id_client, c.id_client) AS id_client,
        count(1) AS c
    FROM match_5a_cm m
    FULL OUTER JOIN all_users_5a u
        ON u.id_user = m.id_user
    FULL OUTER JOIN all_contacts_casamineira c
        ON c.id_client = m.id_client
    GROUP BY 1, 2
)
, all_contacts_users_and_clients AS (
    SELECT
        uc.id_user,
        uc.id_client,
        COALESCE(u.email,c.email) AS email,
        COALESCE(u.phone_number, c.phone_number) AS phone_number
    FROM unique_users_and_clients uc
    LEFT JOIN all_users_5a u
        ON u.id_user = uc.id_user
    LEFT JOIN all_contacts_casamineira c
        ON c.id_client = uc.id_client
UNION ALL
    SELECT
        uc.id_user,
        uc.id_client,
        COALESCE(c.email,u.email) AS email,
        COALESCE(c.phone_number, u.phone_number) AS phone_number
    FROM unique_users_and_clients uc
    LEFT JOIN all_contacts_casamineira c
        ON c.id_client = uc.id_client
    LEFT JOIN all_users_5a u
        ON u.id_user = uc.id_user
)
, lead_classified_adjust_phone AS (
    WITH clean_phone AS (
        SELECT
            lrw.id_lead,
            REGEXP_SUBSTR(lrw.user_phone_number,'[0-9]+') AS user_phone_number,
            REGEXP_SUBSTR(c.user_ddd,'[0-9]+') AS user_ddd,
            c.ts_received AS ts_first_contact
        FROM datalake_classified_leads_clean_prod.lead_reply_whatsapp lrw
        JOIN datalake_classified_leads_clean_prod.lead_contact c
            ON c.id = lrw.id_lead
        WHERE c.business_context = 'SALE'
            -- spam registries that must be dropped
            AND c.ts_received::date||c.id_property != '2021-07-30893359741'
    )
    , first_contact_by_phone AS (
        SELECT
            cp.id_lead,
            cp.ts_first_contact,
            CASE
                WHEN LENGTH(user_phone_number) IN (11,10) AND SUBSTRING(user_phone_number,1,2) = '55' THEN '+55'||COALESCE(NULLIF(user_ddd,''),'11')||SUBSTRING(user_phone_number,3)
                WHEN LENGTH(user_phone_number) IN (11,10) AND SUBSTRING(user_phone_number,1,2) != '55' THEN '+55'||user_phone_number
                WHEN LENGTH(user_phone_number) IN (8,9) THEN '+55'||COALESCE(NULLIF(user_ddd,''),'11')||user_phone_number
                WHEN LENGTH(user_phone_number) < 8 THEN NULL
                ELSE '+'||user_phone_number
            END AS phone_number,
            ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY cp.ts_first_contact) AS rw,
            COUNT(1) OVER (PARTITION BY phone_number) AS count_classified_contacts
        FROM clean_phone cp
        WHERE RIGHT(phone_number,7) NOT IN ('1111111','9999999','0000000','1212121','3456789','1234567','2222222','3333333','4444444','5555555','6666666','7777777','8888888','9999991')
    )
    SELECT
        *
    FROM first_contact_by_phone
    WHERE rw = 1
)
, lead_classified_email AS (
    WITH first_contact_by_email AS (
        SELECT
            c.id AS id_lead,
            LOWER(lre.user_email) AS email,
            c.ts_received AS ts_first_contact,
            ROW_NUMBER() OVER (PARTITION BY email ORDER BY c.ts_received) AS rw,
            COUNT(1) OVER (PARTITION BY email) AS count_classified_contacts
        FROM  datalake_classified_leads_clean_prod.lead_contact c
        JOIN  datalake_classified_leads_clean_prod.lead_reply_email lre
            ON c.id = lre.id_lead
        WHERE c.business_context = 'SALE'
            -- spam registries that must be dropped
            AND c.ts_received::date||c.id_property != '2021-07-30893359741'
    )
    SELECT
        *
    FROM first_contact_by_email
    WHERE rw = 1
)
, all_user_client_lead_classifieds AS (
    SELECT
        uc.id_user,
        uc.id_client AS id_secretariat_client,
        CASE WHEN LEAST(lpe.ts_first_contact,lpp.ts_first_contact) = lpe.ts_first_contact THEN lpe.id_lead ELSE lpp.id_lead END AS id_classified_lead,
        COALESCE(NULLIF(uc.id_user||'_5a', '_5a'),NULLIF(uc.id_client||'_cm', '_cm'), NULLIF(id_classified_lead||'_lc', '_lc')) AS user_key,
        COALESCE(lpe.email, uc.email) AS email,
        COALESCE(lpp.phone_number,uc.phone_number) AS phone_number
    FROM all_contacts_users_and_clients uc
    FULL OUTER JOIN lead_classified_adjust_phone lpp
        ON lpp.phone_number = uc.phone_number
    FULL OUTER JOIN lead_classified_email lpe
        ON lpe.email = uc.email
)
, unique_user_client_lead_classifieds AS (
    SELECT
        u.id_user,
        u.id_secretariat_client,
        u.id_classified_lead,
        u.user_key,
        COUNT(1) AS c
    FROM all_user_client_lead_classifieds u
    GROUP BY 1, 2, 3, 4
)
, unique_users_list_ids AS (
    SELECT
        au.user_key,
        au.id_user,
        LISTAGG(DISTINCT au.id_secretariat_client,'/') AS list_id_secretariat_client,
        LISTAGG(DISTINCT au.id_classified_lead,'/') AS list_id_classified_lead,
        LISTAGG(DISTINCT au.email,'/') AS list_emails,
        LISTAGG(DISTINCT au.phone_number,'/') AS list_phone_numbers
    FROM all_user_client_lead_classifieds au
    GROUP BY 1, 2
)
, lead_classifieds_info AS (
    WITH first_classified AS (
        SELECT
            uu.user_key,
            uu.id_classified_lead,
            c.id_property AS id_house_first_classified_intent,
            fl.sk_region AS sk_region_classified,
            c.origin_partner AS classified_partner,
            c.ts_received AS ts_classified_first_intent,
            ROW_NUMBER() OVER (PARTITION BY uu.user_key ORDER BY c.ts_received) AS rw -- first row for each user_key
        FROM unique_user_client_lead_classifieds uu
        JOIN datalake_classified_leads_clean_prod.lead_contact c
            ON c.id = uu.id_classified_lead
        LEFT JOIN sale.fact_listings fl
            ON fl.sk_house = c.id_property
        )
    SELECT
        *
    FROM first_classified
    WHERE rw = 1
)
, casamineira_secretariat_info AS (
    WITH first_secretariat_contact AS (
        SELECT
            uu.user_key,
            uu.id_secretariat_client,
            h.id_house_quintoandar,
            c.id_house AS id_house_cm,
            cth.city_name AS city_secretariat_contact,
            oc.origin_contact_name AS secretariat_contact_origin,
            mc.media_contact_name AS secretariat_contact_midia,
            fl.sk_region AS sk_region_secretariat_contact,
            CONVERT_TIMEZONE('BRT', 'UTC', c.ts_created)  AS ts_first_secretariat_contact,
            ROW_NUMBER() OVER (PARTITION BY  uu.user_key ORDER BY c.ts_created) AS rw  -- first row for each user_key
        FROM unique_user_client_lead_classifieds uu
        JOIN datalake_casa_mineira_crm_clean_prod.contact c
            ON c.id_client = uu.id_secretariat_client
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.origin_contact oc
            ON oc.id = c.id_origin
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.media_contact mc
            ON mc.id = c.id_media
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house h
            ON h.id = c.id_house
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.neighborhood nh
            ON nh.id = h.id_neighborhood
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.city cth
            ON cth.id = nh.id_city
        LEFT JOIN sale.fact_listings fl
            ON fl.sk_house = h.id_house_quintoandar
        )
    SELECT
        *
    FROM first_secretariat_contact
    WHERE rw = 1
)
, first_booking_casamineira AS (
    WITH first_booking AS (
        SELECT
            uu.user_key,
            uu.id_secretariat_client,
            v.id_house AS id_house_cm,
            h.id_house_quintoandar,
            cth.city_name AS city_first_booking_cm,
            fl.sk_region AS sk_region_first_booking_cm,
            CONVERT_TIMEZONE('BRT', 'UTC', v.ts_created) AS ts_booking_created_cm,
            ROW_NUMBER() OVER (PARTITION BY uu.user_key ORDER BY v.ts_created) AS rw  -- first row for each user_key
        FROM unique_user_client_lead_classifieds uu
        JOIN datalake_casa_mineira_crm_clean_prod.visit v
            ON v.id_client = uu.id_secretariat_client
        JOIN datalake_casa_mineira_crm_clean_prod.house h
            ON h.id = v.id_house
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.neighborhood nh
            ON nh.id = h.id_neighborhood
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.city cth
            ON cth.id = nh.id_city
        LEFT JOIN sale.fact_listings fl
            ON fl.sk_house = h.id_house_quintoandar
    )
    SELECT
        *
    FROM first_booking
    WHERE rw = 1
)
, first_visit_casamineira AS (
    WITH first_visit AS (
        SELECT
            uu.user_key,
            uu.id_secretariat_client,
            CONVERT_TIMEZONE('BRT', 'UTC', v.ts_visited) AS ts_visit_completed_cm,
            ROW_NUMBER() OVER (PARTITION BY uu.user_key ORDER BY v.ts_visited) AS rw  -- first row for each user_key
        FROM unique_user_client_lead_classifieds uu
        JOIN datalake_casa_mineira_crm_clean_prod.visit v
            ON v.id_client = uu.id_secretariat_client
        JOIN datalake_casa_mineira_crm_clean_prod.house h
            ON h.id = v.id_house
        WHERE
            v.validation_type ='confirmado'
            AND is_virtual IS FALSE
    )
    SELECT
        *
    FROM first_visit
    WHERE rw = 1
)
, first_visit_intent_events_info AS (
    WITH first_vic AS (
        SELECT
            CAST(e.id_user AS BIGINT) AS id_user,
            CAST(e.ts_event AS TIMESTAMP) AS ts_visit_intent,
            dr.sk_region,
            ROW_NUMBER() OVER (PARTITION BY e.id_user ORDER BY e.ts_event) AS rw -- get first row for each user
        FROM datalake_amplitude_clean_prod.events e
        LEFT JOIN sale.fact_listings fl
            ON CAST(fl.sk_house AS VARCHAR) = TRIM(JSON_EXTRACT_PATH_TEXT(e.event_properties, 'house_id'))
        LEFT JOIN dim_region dr
            ON dr.sk_region = fl.sk_region
        WHERE
            e.event_type IN ('visit_intent_clicked','visit_schedule_clicked', 'schedule_page_viewed', 'visit_schedule_confirmed')
            AND CAST(TRIM(JSON_EXTRACT_PATH_TEXT(event_properties, 'business_context')) AS VARCHAR) IN ('sale','SALE')
            AND e.id_app = 170698
            AND CAST(e.ts_event AS DATE) >= CAST('2020-01-01' AS DATE)
            AND e.id_user IS NOT NULL
    )
    SELECT
        id_user,
        sk_region AS sk_region_visit_intent,
        ts_visit_intent AS ts_first_visit_scheduling_event
    FROM first_vic
    WHERE rw = 1
)
, first_booking_quintoandar AS (
    WITH first_booking AS (
        SELECT
            fv.sk_buyer AS id_user,
            fv.sk_house AS id_house,
            fv.sk_region AS sk_region_first_booking_5a,
            db.dt_created AS ts_booking_created_5a,
            ROW_NUMBER() OVER (PARTITION BY fv.sk_buyer ORDER BY db.dt_created) AS rw
        FROM sale.fact_visits fv
        LEFT JOIN dim_booking db
            ON db.sk_booking = fv.sk_booking
        )
    SELECT
        *
    FROM first_booking
    WHERE rw =1
)
, first_visit_quintoandar AS (
    WITH first_visit AS (
        SELECT
            fv.sk_buyer AS id_user,
            db.dt_scheduling AS ts_visit_completed_5a,
            ROW_NUMBER() OVER (PARTITION BY fv.sk_buyer ORDER BY db.dt_created) AS rw
        FROM sale.fact_visits fv
        LEFT JOIN dim_booking db
            ON db.sk_booking = fv.sk_booking
        WHERE fv.sk_visit_completed_date > 0
        )
    SELECT
        *
    FROM first_visit
    WHERE rw =1
)
, offers_and_ccvs AS (
    WITH all_offers AS (
        SELECT
            uu.user_key,
            fo.sk_offer,
            CASE
                WHEN oh.offer_flow LIKE '%HUB%' THEN 'HUB'
                WHEN oh.offer_flow = 'CENTRAL' THEN 'CENTRAL'
                ELSE 'DealMaking'
            END AS offer_flow,
            fo.sk_region AS sk_region_first_offer,
            TO_DATE(fo.sk_offer_submitted_date, 'YYYYMMDD') AS dt_offer_submitted,
            COALESCE(TO_DATE(NULLIF(fo.sk_sale_agreement_signed_date,-1), 'YYYYMMDD'), oh.dt_sale_agreement_signed) AS dt_sale_agreement_signed
        FROM unique_user_client_lead_classifieds uu
        JOIN sale.fact_offers fo
            ON fo.sk_buyer = uu.id_user
        LEFT JOIN datalake_gsheets_clean_prod.offers_hub_central oh
            ON oh.id_offer = fo.sk_offer
    UNION ALL
        -- HUB v0 offer flow
        SELECT
            uu.user_key,
            oh.id_offer AS sk_offer,
            oh.offer_flow,
            fl.sk_region AS sk_region_first_offer,
            oh.dt_offer_submitted,
            oh.dt_sale_agreement_signed
        FROM unique_user_client_lead_classifieds uu
        JOIN datalake_gsheets_clean_prod.offers_hub_central oh
            ON uu.id_user = oh.id_user_5a
            OR uu.id_secretariat_client = oh.id_client_cm
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house h
            ON h.id = oh.id_house_cm
        LEFT JOIN sale.fact_listings fl
            ON fl.sk_house = h.id_house_quintoandar
        WHERE
            oh.offer_flow in ('HUB_VM_V0','HUB_BV_V0')
            AND oh.dt_offer_submitted IS NOT NULL
    )
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY user_key ORDER BY dt_offer_submitted) AS rw_offer,
        ROW_NUMBER() OVER (PARTITION BY user_key ORDER BY dt_sale_agreement_signed) AS rw_ccv
    FROM all_offers
    )
, first_offer AS (
    SELECT
        *
    FROM offers_and_ccvs
    WHERE rw_offer = 1
)
, first_ccv AS (
    SELECT
        *
    FROM offers_and_ccvs
    WHERE rw_ccv = 1
        AND dt_sale_agreement_signed IS NOT NULL
)
, final_base AS (
    SELECT
        uu.user_key,
        uu.id_user,
        COALESCE(csi.id_secretariat_client,fbcm.id_secretariat_client) AS id_secretariat_client,
        lci.id_classified_lead,
        COALESCE(lci.sk_region_classified,-1) AS sk_region_classified,
        COALESCE(csi.sk_region_secretariat_contact,-1) AS sk_region_secretariat_contact,
        COALESCE(fbcm.sk_region_first_booking_cm,-1) AS sk_region_booking_cm,
        COALESCE(vie.sk_region_visit_intent,-1) AS sk_region_visit_intent,
        COALESCE(fbq.sk_region_first_booking_5a,-1) AS sk_region_booking_5a,
        CASE
            WHEN LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted) = lci.ts_classified_first_intent
                THEN 'Classified'
            WHEN LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted) = csi.ts_first_secretariat_contact
                THEN 'Secretariat'
            WHEN LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted) = vie.ts_first_visit_scheduling_event
                THEN 'Visit_scheduling_event'
            WHEN LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted)  = fbq.ts_booking_created_5a
                THEN 'Booking'
            WHEN LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted)  = fo.dt_offer_submitted
                THEN 'Offer_submitted'
        END AS first_touch,
        CASE WHEN uu.id_user IS NOT NULL THEN '5A_' ELSE '' END
            ||
            CASE WHEN csi.id_secretariat_client IS NOT NULL THEN 'CM_' ELSE '' END
            ||
            CASE WHEN lci.id_classified_lead IS NOT NULL THEN 'Classified' ELSE '' END
        AS system_users,
        COALESCE(CASE
            WHEN first_touch = 'Classified' THEN lci.sk_region_classified
            WHEN first_touch = 'Secretariat' THEN COALESCE(csi.sk_region_secretariat_contact,fbcm.sk_region_first_booking_cm,vie.sk_region_visit_intent,fbq.sk_region_first_booking_5a,lci.sk_region_classified)
            WHEN first_touch = 'Visit_scheduling_event' THEN vie.sk_region_visit_intent
            WHEN first_touch = 'Booking' THEN fbq.sk_region_first_booking_5a
            WHEN first_touch = 'Offer_submitted' THEN fo.sk_region_first_offer
        END,-1) AS sk_first_region,
        lci.classified_partner,
        CASE
            WHEN csi.ts_first_secretariat_contact IS NOT NULL AND DATE_DIFF('min', fbq.ts_booking_created_5a, csi.ts_first_secretariat_contact) > - 4
                THEN 'with_previous_booking'
            WHEN csi.ts_first_secretariat_contact IS NOT NULL
                THEN 'no_previous_booking'
        END AS secretariat_first_contact_type,
        csi.city_secretariat_contact,
        csi.secretariat_contact_origin,
        csi.secretariat_contact_midia,
        fbcm.city_first_booking_cm,
        fo.offer_flow,
        fc.offer_flow AS ccv_flow,
         LEAST(lci.ts_classified_first_intent, csi.ts_first_secretariat_contact, vie.ts_first_visit_scheduling_event, fbq.ts_booking_created_5a,fo.dt_offer_submitted) AS ts_first_visit_lead_intent,
        lci.ts_classified_first_intent,
        csi.ts_first_secretariat_contact,
        vie.ts_first_visit_scheduling_event,
        fbq.ts_booking_created_5a AS ts_first_booking_created_5a,
        vq.ts_visit_completed_5a AS ts_first_visit_completed_5a,
        fbcm.ts_booking_created_cm AS ts_first_booking_created_cm,
        vcm.ts_visit_completed_cm AS ts_first_visit_completed_cm,
        LEAST(fbq.ts_booking_created_5a,fbcm.ts_booking_created_cm) AS ts_first_booking,
        LEAST(vcm.ts_visit_completed_cm,vq.ts_visit_completed_5a) AS ts_first_visit_completed,
        fo.dt_offer_submitted AS dt_first_offer_submitted,
        fc.dt_sale_agreement_signed,
        list_id_secretariat_client,
        list_id_classified_lead
    FROM unique_users_list_ids uu
    LEFT JOIN lead_classifieds_info lci
        ON lci.user_key = uu.user_key
    LEFT JOIN casamineira_secretariat_info csi
        ON csi.user_key = uu.user_key
    LEFT JOIN first_booking_casamineira fbcm
        ON fbcm.user_key = uu.user_key
    LEFT JOIN first_visit_intent_events_info vie
        ON vie.id_user = uu.id_user
    LEFT JOIN first_booking_quintoandar fbq
        ON fbq.id_user = uu.id_user
    LEFT JOIN first_visit_casamineira vcm
        ON vcm.user_key = uu.user_key
    LEFT JOIN first_visit_quintoandar vq
        ON vq.id_user = uu.id_user
    LEFT JOIN first_offer fo
        ON fo.user_key = uu.user_key
    LEFT JOIN first_ccv fc
        ON fc.user_key = uu.user_key
)
SELECT
    *
FROM final_base
WHERE first_touch IS NOT NULL