WITH all_users_5a AS (
    SELECT
        id_user,
        TRIM(email) AS email,
        phone_number
    FROM
        datalake_sale_lead_flows.quintoandar_lead_flow
),
expanded_emails_casa_mineira AS (
    SELECT
        id_secretariat_client,
        EXPLODE_OUTER(list_emails) AS email,
        list_phone_numbers
    FROM
        datalake_sale_lead_flows.casa_mineira_lead_flow
),
all_contacts_casa_mineira AS (
    SELECT
        id_secretariat_client,
        email,
        EXPLODE_OUTER(list_phone_numbers) AS phone_number
    FROM
        expanded_emails_casa_mineira
),
match_email AS (
    SELECT
        u.id_user,
        c.id_secretariat_client
    FROM 
        all_users_5a AS u
    JOIN
        all_contacts_casa_mineira AS c
            ON u.email = c.email
),
match_phone AS (
    SELECT
        u.id_user,
        c.id_secretariat_client
    FROM 
        all_users_5a AS u
    JOIN
        all_contacts_casa_mineira AS c
            ON u.phone_number = c.phone_number
    LEFT JOIN
        match_email AS me
            ON me.id_user = u.id_user
            OR me.id_secretariat_client = c.id_secretariat_client
    WHERE
        me.id_user IS NULL
        AND me.id_secretariat_client IS NULL
),
match_5a_cm AS (
    SELECT
        me.id_user,
        me.id_secretariat_client
    FROM
        match_email AS me
    UNION ALL
    SELECT
        mp.id_user,
        mp.id_secretariat_client
    FROM
        match_phone AS mp
),
unique_users_and_clients AS (
    SELECT
        COALESCE(m.id_user, u.id_user) AS id_user,
        COALESCE(m.id_secretariat_client, c.id_secretariat_client) AS id_secretariat_client,
        count(1) AS c
    FROM
        match_5a_cm AS m
    FULL OUTER JOIN
        all_users_5a AS u
            ON u.id_user = m.id_user
    FULL OUTER JOIN
        all_contacts_casa_mineira AS c
            ON c.id_secretariat_client = m.id_secretariat_client
    GROUP BY
        1, 2
),
all_contacts_users_and_clients AS (
    SELECT
        uc.id_user,
        uc.id_secretariat_client,
        COALESCE(u.email,c.email) AS email,
        COALESCE(u.phone_number, c.phone_number) AS phone_number
    FROM
        unique_users_and_clients AS uc
    LEFT JOIN
        all_users_5a AS u
            ON u.id_user = uc.id_user
    LEFT JOIN
        all_contacts_casa_mineira AS c
            ON c.id_secretariat_client = uc.id_secretariat_client
    UNION ALL
    SELECT
        uc.id_user,
        uc.id_secretariat_client,
        COALESCE(c.email,u.email) AS email,
        COALESCE(c.phone_number, u.phone_number) AS phone_number
    FROM
        unique_users_and_clients AS uc
    LEFT JOIN
        all_contacts_casa_mineira AS c
            ON c.id_secretariat_client = uc.id_secretariat_client
    LEFT JOIN
        all_users_5a AS u
            ON u.id_user = uc.id_user
),
classified_leads_numbered_by_contact AS (
    SELECT
        id_classified_lead,
        phone_number,
        email,
        ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY ts_intent) AS rw_phone_asc,
        ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY ts_intent DESC) AS rw_phone_desc,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_intent) AS rw_email_asc,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_intent DESC) AS rw_email_desc,
        ts_intent
    FROM
        datalake_sale_lead_flows.classified_lead_flow
),
first_classified_phone_lead AS (
    SELECT
        id_classified_lead,
        phone_number,
        ts_intent
    FROM
        classified_leads_numbered_by_contact
    WHERE
        rw_phone_asc = 1
),
last_classified_phone_lead AS (
    SELECT
        id_classified_lead,
        phone_number,
        ts_intent
    FROM
        classified_leads_numbered_by_contact
    WHERE
        rw_phone_desc = 1
),
first_classified_email_lead AS (
    SELECT
        id_classified_lead,
        email,
        ts_intent
    FROM
        classified_leads_numbered_by_contact
    WHERE
        rw_email_asc = 1
),
last_classified_email_lead AS (
    SELECT
        id_classified_lead,
        email,
        ts_intent
    FROM
        classified_leads_numbered_by_contact
    WHERE
        rw_email_desc = 1
),
aux_all_leads_classified AS (
    SELECT
        uc.id_user,
        uc.id_secretariat_client,
        CASE 
            WHEN LEAST(fcel.ts_intent, fcpl.ts_intent) = fcel.ts_intent THEN fcel.id_classified_lead 
            ELSE fcpl.id_classified_lead 
        END AS id_first_classified_lead,
        COALESCE(fcel.email, uc.email) AS email,
        COALESCE(fcpl.phone_number, uc.phone_number) AS phone_number
    FROM 
        all_contacts_users_and_clients AS uc
    FULL OUTER JOIN
        first_classified_phone_lead AS fcpl
            ON fcpl.phone_number = uc.phone_number
    FULL OUTER JOIN
        first_classified_email_lead AS fcel
            ON fcel.email = uc.email
),
all_leads_classified AS (
    SELECT
        a.*,
        CASE 
            WHEN GREATEST(lcel.ts_intent, lcpl.ts_intent) = lcel.ts_intent THEN lcel.id_classified_lead 
            ELSE lcpl.id_classified_lead 
        END AS id_last_classified_lead,
        COALESCE(
            NULLIF(id_user||'_5a', '_5a'),
            NULLIF(id_secretariat_client||'_cm', '_cm'),
            NULLIF(id_first_classified_lead||'_lc', '_lc')
        ) AS id_lead
    FROM
        aux_all_leads_classified AS a
    LEFT JOIN
        last_classified_phone_lead AS lcpl
            ON a.phone_number = lcpl.phone_number
    LEFT JOIN
        last_classified_email_lead AS lcel
            ON a.email = lcel.email
),
hub_leads_numbered_by_contact AS (
    SELECT
        id_visitor,
        phone_number,
        email,
        ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY ts_first_visit_lead_intent) AS rw_phone_asc,
        ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY ts_last_visit_lead_intent) AS rw_phone_desc,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_first_visit_lead_intent) AS rw_email_asc,
        ROW_NUMBER() OVER (PARTITION BY email ORDER BY ts_last_visit_lead_intent) AS rw_email_desc,
        ts_first_visit_lead_intent,
        ts_last_visit_lead_intent
    FROM
        datalake_sale_lead_flows.hub_services_lead_flow
),
first_hub_phone_lead AS (
    SELECT
        id_visitor,
        phone_number,
        ts_first_visit_lead_intent
    FROM
        hub_leads_numbered_by_contact
    WHERE
        rw_phone_asc = 1
),
last_hub_phone_lead AS (
    SELECT
        id_visitor,
        phone_number,
        ts_last_visit_lead_intent
    FROM
        hub_leads_numbered_by_contact
    WHERE
        rw_phone_desc = 1
),
first_hub_email_lead AS (
    SELECT
        id_visitor,
        email,
        ts_first_visit_lead_intent
    FROM
        hub_leads_numbered_by_contact
    WHERE
        rw_phone_asc = 1
),
last_hub_email_lead AS (
    SELECT
        id_visitor,
        email,
        ts_last_visit_lead_intent
    FROM
        hub_leads_numbered_by_contact
    WHERE
        rw_phone_desc = 1
),
aux_all_leads AS ( 
    SELECT
        alc.id_user, 
        alc.id_lead AS id_aux_lead,
        alc.id_secretariat_client,
        CASE 
            WHEN LEAST(fhel.ts_first_visit_lead_intent, fhpl.ts_first_visit_lead_intent) = fhel.ts_first_visit_lead_intent
                THEN fhel.id_visitor
            ELSE fhpl.id_visitor 
        END AS id_first_hub_lead,
        alc.id_first_classified_lead,
        alc.id_last_classified_lead,
        COALESCE(fhel.email, alc.email) AS email,
        COALESCE(fhpl.phone_number, alc.phone_number) AS phone_number
    FROM 
        all_leads_classified AS alc
    FULL OUTER JOIN
        first_hub_phone_lead AS fhpl
            ON fhpl.phone_number = alc.phone_number
    FULL OUTER JOIN
        first_hub_email_lead AS fhel
            ON fhel.email = alc.email
),
all_leads AS (
    SELECT
        a.*,
        CASE 
            WHEN GREATEST(lhel.ts_last_visit_lead_intent, lhpl.ts_last_visit_lead_intent) = lhel.ts_last_visit_lead_intent
                THEN lhel.id_visitor 
            ELSE lhpl.id_visitor 
        END AS id_last_hub_lead,
        COALESCE(
            a.id_aux_lead,
            NULLIF(id_first_hub_lead||'_hb', '_hb')
        ) AS id_lead
    FROM
        aux_all_leads AS a
    LEFT JOIN
        last_hub_phone_lead AS lhpl
            ON a.phone_number = lhpl.phone_number
    LEFT JOIN
        last_hub_email_lead AS lhel
            ON a.email = lhel.email
),
aux_unique_leads AS (
    SELECT DISTINCT
        u.id_user,
        u.id_secretariat_client,
        u.id_first_classified_lead,
        u.id_last_classified_lead,
        u.id_first_hub_lead,
        u.id_last_hub_lead,
        u.id_lead
    FROM 
        all_leads AS u
),
rw_filter_leads AS (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY id_first_hub_lead ORDER BY id_user NULLS LAST, id_secretariat_client NULLS LAST, id_first_classified_lead NULLS LAST) AS rw_hb,
      ROW_NUMBER() OVER (PARTITION BY id_first_classified_lead ORDER BY id_user NULLS LAST, id_secretariat_client NULLS LAST, id_first_hub_lead NULLS LAST) AS rw_cl
    FROM 
      aux_unique_leads
),
unique_leads AS (
  SELECT
      id_user,
      id_secretariat_client,
      id_first_classified_lead,
      id_last_classified_lead,
      id_first_hub_lead,
      id_last_hub_lead,
      id_lead
  FROM
      rw_filter_leads
  WHERE
      (id_user IS NOT NULL
      OR id_secretariat_client IS NOT NULL)
      OR (
          id_first_classified_lead IS NOT NULL
          AND rw_cl = 1
      )
      OR (
          id_first_hub_lead IS NOT NULL
          AND rw_hb = 1
      )
),
unique_deduplicated_leads AS (
    SELECT DISTINCT
        au.id_lead,
        au.id_user,
        CASE
            WHEN array_contains(collect_set(accm.has_secretariat_contact_created), TRUE) THEN TRUE
            ELSE FALSE
        END AS casa_mineira_has_secretariat_contact_created,
        CASE
            WHEN array_contains(collect_set(accm.has_first_booking), TRUE) THEN TRUE
            ELSE FALSE
        END AS casa_mineira_has_first_booking,
        collect_set(accm.further_funnel_step) AS casa_mineira_further_funnel_step_list,
        SUM(accm.total_bookings_created) AS casa_mineira_total_bookings_created,
        SUM(accm.total_bookings_canceled) AS casa_mineira_total_bookings_canceled,
        SUM(accm.total_visits_completed) AS casa_mineira_total_visits_completed,
        SUM(accm.total_offers_submitted) AS casa_mineira_total_offers_submitted,
        SUM(accm.total_sale_agreements_signed) AS casa_mineira_total_sale_agreements_signed
    FROM
        all_leads AS au
    LEFT JOIN
        datalake_sale_lead_flows.casa_mineira_lead_flow AS accm
            ON au.id_secretariat_client = accm.id_secretariat_client 
    GROUP BY 1, 2
),
casa_mineira_leads AS (
    SELECT
        uu.id_lead,
        c.*,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_contact_prospect NULLS LAST) AS rw_asc_contact_prospect,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_contact_prospect DESC NULLS LAST) AS rw_desc_contact_prospect,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_combo_event_contact_prospect NULLS LAST) AS rw_asc_combo_event,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_combo_event_contact_prospect DESC NULLS LAST) AS rw_desc_combo_event,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_booking_created NULLS LAST) AS rw_asc_booking,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_booking_created DESC NULLS LAST) AS rw_desc_booking,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_visit_completed NULLS LAST) AS rw_asc_visit,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_visit_completed DESC NULLS LAST) AS rw_desc_visit,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_offer_submitted NULLS LAST) AS rw_asc_offer,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_offer_submitted DESC NULLS LAST) AS rw_desc_offer,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_first_sale_agreement_signed NULLS LAST) AS rw_asc_ccv,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_last_sale_agreement_signed DESC NULLS LAST) AS rw_desc_ccv
    FROM
        unique_leads AS uu
    JOIN
        datalake_sale_lead_flows.casa_mineira_lead_flow AS c
            ON c.id_secretariat_client = uu.id_secretariat_client
),
first_classified_leads AS (
    SELECT
        uu.id_lead,
        c.*,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_intent) AS rw_asc
    FROM
        unique_leads AS uu
    JOIN
        datalake_sale_lead_flows.classified_lead_flow AS c
            ON c.id_classified_lead = uu.id_first_classified_lead
),
last_classified_leads AS (
    SELECT
        uu.id_lead,
        c.*,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY c.ts_intent DESC) AS rw_desc
    FROM
        unique_leads AS uu
    JOIN
        datalake_sale_lead_flows.classified_lead_flow AS c
            ON c.id_classified_lead = uu.id_last_classified_lead
),
first_hub_leads AS (
    SELECT 
        uu.id_lead,
        h.*,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY h.ts_first_visit_lead_intent) AS rw_asc
    FROM
        unique_leads AS uu
    JOIN
        datalake_sale_lead_flows.hub_services_lead_flow AS h
        ON h.id_visitor = uu.id_first_hub_lead
),
last_hub_leads AS (
    SELECT
        uu.id_lead,
        h.*,
        ROW_NUMBER() OVER (PARTITION BY uu.id_lead ORDER BY h.ts_last_visit_lead_intent DESC) AS rw_desc
    FROM
        unique_leads AS uu
    JOIN
        datalake_sale_lead_flows.hub_services_lead_flow AS h
            ON h.id_visitor = uu.id_last_hub_lead
),
final_base AS (
    SELECT 
        uu.id_lead,
        uu.id_user,
        COALESCE(fcm_cp.id_secretariat_client, fcm_bk.id_secretariat_client) AS id_secretariat_client,
        fcl.id_classified_lead,
        fhb.id_visitor AS id_visitor_hub_service,
        fcl.id_region AS id_region_classified,
        CASE LEAST(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect)
            WHEN fcm_cp.ts_first_contact_prospect THEN COALESCE(fcm_cp.id_first_region_contact_prospect, fhb.id_first_contact_prospect_region)
            ELSE COALESCE(fhb.id_first_contact_prospect_region, fcm_cp.id_first_region_contact_prospect)
        END AS id_region_contact_prospect,
        fcm_bk.id_first_region_booking AS id_region_booking_cm,
        qa.id_region_first_visit_intent AS id_region_visit_intent,
        qa.id_region_first_booking AS id_region_booking_5a,
        CASE LEAST(fcl.ts_intent, fcm_cp.ts_first_contact_prospect, qa.ts_first_visit_scheduling_event, qa.ts_first_booking_created, qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted, fhb.ts_first_visit_lead_intent)
            WHEN fcl.ts_intent THEN fcl.id_region
            WHEN fcm_cp.ts_first_contact_prospect
                THEN COALESCE(fcm_cp.id_first_region_contact_prospect,fcm_bk.id_first_region_booking, qa.id_region_first_visit_intent, qa.id_region_first_booking, fcl.id_region)
            WHEN qa.ts_first_visit_scheduling_event THEN qa.id_region_first_visit_intent
            WHEN qa.ts_first_booking_created THEN qa.id_region_first_booking
            WHEN qa.ts_first_offer_submitted THEN qa.id_region_first_offer
            WHEN fcm_o.ts_first_offer_submitted THEN fcm_o.id_first_region_offer
            WHEN fhb.ts_first_visit_lead_intent THEN fhb.id_first_region
        END AS id_first_region,
        CASE LEAST(fcl.ts_intent, fcm_cp.ts_first_contact_prospect, qa.ts_first_visit_scheduling_event, qa.ts_first_booking_created, qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted, fhb.ts_first_visit_lead_intent)
            WHEN fcl.ts_intent THEN fcl.id_house
            WHEN fcm_cp.ts_first_contact_prospect
                THEN COALESCE(fcm_cp.id_first_house_5a_secretariat_contact, fcm_bk.id_first_house_5a_booking, qa.id_house_first_visit_intent, qa.id_house_first_booking, fcl.id_house)
            WHEN qa.ts_first_visit_scheduling_event THEN qa.id_house_first_visit_intent
            WHEN qa.ts_first_booking_created THEN qa.id_house_first_booking
            WHEN qa.ts_first_offer_submitted THEN qa.id_house_first_offer
            WHEN fhb.ts_first_visit_lead_intent THEN fhb.id_first_house
        END AS id_first_house,
        qa.id_house_first_sale_agreement AS id_first_house_sale_agreement,
        CASE LEAST(fcl.ts_intent, fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect, qa.ts_first_visit_scheduling_event, qa.ts_first_booking_created, LEAST(qa.ts_first_offer_submitted,fcm_o.ts_first_offer_submitted))
            WHEN fcl.ts_intent THEN 'Classified'
            WHEN LEAST(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect) THEN 'Secretariat'
            WHEN qa.ts_first_visit_scheduling_event THEN 'Visit_scheduling_event'
            WHEN qa.ts_first_booking_created THEN 'Booking'
            WHEN LEAST(qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted) THEN 'Offer_submitted'
        END AS first_touch,
        fcl.origin_partner AS first_classified_partner,
        CASE LEAST(qa.ts_first_visit_scheduling_event, fcm_cp.ts_first_contact_prospect, fhb.ts_first_visit_lead_intent)
            WHEN qa.ts_first_visit_scheduling_event THEN qa.first_business_unit_region_intent_lead
            WHEN fcm_cp.ts_first_contact_prospect THEN fcm_cp.first_business_unit_region_intent_lead
            WHEN fhb.ts_first_visit_lead_intent THEN fhb.first_business_unit_hub_name
        END AS first_business_unit_region_intent_lead,
        CASE GREATEST(qa.ts_last_visit_scheduling_event, lcm_cp.ts_last_contact_prospect, lhb.ts_last_visit_lead_intent)
            WHEN qa.ts_last_visit_scheduling_event THEN qa.last_business_unit_region_intent_lead
            WHEN lcm_cp.ts_last_contact_prospect THEN lcm_cp.last_business_unit_region_intent_lead
            WHEN lhb.ts_last_visit_lead_intent THEN lhb.last_business_unit_hub_name
        END AS last_business_unit_region_intent_lead,
        CASE 
            WHEN LEAST(qa.ts_first_booking_created, fcm_bk.ts_first_booking_created) = qa.ts_first_booking_created 
                THEN qa.first_business_unit_region_new_buyer_prospect
            ELSE fcm_bk.first_business_unit_region_new_buyer_prospect
        END AS first_business_unit_region_new_buyer_prospect,
        CASE LEAST(fhb.ts_first_contact_prospect, fcm_cp.ts_first_contact_prospect)
            WHEN fhb.ts_first_contact_prospect THEN fhb.first_contact_prospect_city_name
            ELSE fcm_cp.first_city_contact_prospect
        END AS first_city_contact_prospect,
        COALESCE(CASE LEAST(fhb.ts_first_contact_prospect, fcm_cp.ts_first_contact_prospect)
            WHEN fhb.ts_first_contact_prospect THEN fhb.first_contact_prospect_origin
            ELSE fcm_cp.first_secretariat_contact_origin
        END, 'NOT_SENT_SV') AS first_contact_prospect_origin,
        COALESCE(CASE GREATEST(lhb.ts_last_contact_prospect, lcm_cp.ts_last_contact_prospect)
            WHEN lhb.ts_last_contact_prospect THEN lhb.last_contact_prospect_origin
            ELSE lcm_cp.last_secretariat_contact_origin
        END, 'NOT_SENT_SV') AS last_contact_prospect_origin,
        CASE LEAST(fhb.ts_first_contact_prospect, fcm_cp.ts_first_contact_prospect)
            WHEN fhb.ts_first_contact_prospect THEN fhb.first_contact_prospect_midia
            ELSE fcm_cp.first_secretariat_contact_media
        END AS first_contact_prospect_media,
        CASE GREATEST(lhb.ts_last_contact_prospect, lcm_cp.ts_last_contact_prospect)
            WHEN lhb.ts_last_contact_prospect THEN lhb.last_contact_prospect_midia
            ELSE lcm_cp.last_secretariat_contact_media
        END AS last_contact_prospect_media,
        fcm_bk.first_city_booking AS first_city_booking_cm,
        CASE
            WHEN LEAST(qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted) = qa.ts_first_offer_submitted 
                THEN qa.first_offer_flow
            ELSE fcm_o.first_offer_flow
        END AS first_offer_flow,
        CASE 
            WHEN LEAST(qa.ts_first_sale_agreement_signed, fcm_ccv.ts_first_sale_agreement_signed) = qa.ts_first_sale_agreement_signed 
                THEN qa.first_ccv_flow
            ELSE fcm_ccv.first_ccv_flow
        END AS first_ccv_flow,
        CASE 
            WHEN LEAST(qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted) = qa.ts_first_offer_submitted 
                THEN qa.first_offer_business_unit
            ELSE fcm_o.first_offer_business_unit
        END AS first_offer_business_unit,
        CASE 
            WHEN LEAST(qa.ts_first_sale_agreement_signed, fcm_ccv.ts_first_sale_agreement_signed) = qa.ts_first_sale_agreement_signed 
                THEN qa.first_ccv_business_unit
            ELSE fcm_ccv.first_ccv_business_unit
        END AS first_ccv_business_unit,
        qa.first_booking_creator_5a,
        CASE
            WHEN qa.further_funnel_step = 'sale_agreement_signed' 
            OR array_contains(casa_mineira_further_funnel_step_list, 'sale_agreement_signed')
                THEN 'sale_agreement_signed'
            WHEN qa.further_funnel_step = 'offer_accepted' 
                THEN 'offer_accepted'
            WHEN qa.further_funnel_step = 'offer_submitted' 
            OR array_contains(casa_mineira_further_funnel_step_list, 'offer_submitted')
                THEN 'offer_submitted'
            WHEN qa.further_funnel_step = 'visit_completed' 
            OR array_contains(casa_mineira_further_funnel_step_list, 'visit_completed')
                THEN 'visit_completed'
            WHEN qa.further_funnel_step = 'booking_created' 
            OR array_contains(casa_mineira_further_funnel_step_list, 'booking_created')
                THEN 'booking_created'            
            WHEN qa.further_funnel_step = 'lead_submission' 
            OR array_contains(casa_mineira_further_funnel_step_list, 'lead_submission')
                THEN 'lead_submission'
            WHEN qa.further_funnel_step = 'talk_to_agent'
                THEN 'talk_to_agent' 
            ELSE
                'not_mapped'
        END AS further_funnel_step,          
        GREATEST(uu.casa_mineira_has_secretariat_contact_created, fhb.has_secretariat_contact_created) AS has_secretariat_contact_created,
        CASE
            WHEN COALESCE(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect) IS NOT NULL 
            AND UNIX_TIMESTAMP(DATE_TRUNC('Minute', qa.ts_first_booking_created)) < 
            UNIX_TIMESTAMP(DATE_TRUNC('Minute', LEAST(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect))) + 4 * 60
                THEN TRUE
            WHEN COALESCE(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect) IS NOT NULL
                THEN FALSE
        END AS has_booking_before_secretariat_contact,
        COALESCE(GREATEST(qa.has_first_booking, uu.casa_mineira_has_first_booking), FALSE) AS has_first_booking,
        COALESCE(qa.has_tenant_rental_contract, FALSE) AS has_tenant_rental_contract,
        COALESCE(qa.is_ongoing_tenant_rental_contract, FALSE) AS is_ongoing_tenant_rental_contract,
        COALESCE(qa.has_owner_rental_contract, FALSE) AS has_owner_rental_contract,
        COALESCE(qa.has_rental_visit, FALSE) AS has_rental_visit_intent,
        COALESCE(qa.total_bookings_created_by_secretariat, 0) AS total_bookings_created_by_secretariat,
        (COALESCE(qa.total_bookings_created, 0) + COALESCE(uu.casa_mineira_total_bookings_created, 0)) AS total_bookings_created,
        (COALESCE(qa.total_bookings_canceled, 0) + COALESCE(uu.casa_mineira_total_bookings_canceled, 0)) AS total_bookings_canceled,
        COALESCE(qa.total_visits_completed_by_secretariat, 0) AS total_visits_completed_by_secretariat,
        (COALESCE(qa.total_visits_completed, 0) + COALESCE(uu.casa_mineira_total_visits_completed, 0)) AS total_visits_completed,
        (COALESCE(qa.total_offer_submitted, 0) + COALESCE(uu.casa_mineira_total_offers_submitted, 0)) AS total_offer_submitted,
        (COALESCE(qa.total_sale_agreement_signed, 0) + COALESCE(uu.casa_mineira_total_sale_agreements_signed, 0)) AS total_sale_agreement_signed,
        fhb.ts_first_talk_to_secretariat,
        lhb.ts_last_talk_to_secretariat,
        LEAST(
            fcl.ts_intent,
            fcm_cp.ts_first_contact_prospect,
            qa.ts_first_visit_scheduling_event,
            qa.ts_first_booking_created,
            qa.ts_first_offer_submitted,
            fcm_o.ts_first_offer_submitted,
            fhb.ts_first_visit_lead_intent,
            qa.ts_first_tta_message_sent
        ) AS ts_first_visit_lead_intent,
        GREATEST(
            lcl.ts_intent,
            lcm_cp.ts_last_contact_prospect,
            qa.ts_last_visit_scheduling_event,
            qa.ts_last_booking_created,
            qa.ts_last_offer_submitted,
            lcm_o.ts_last_offer_submitted,
            lhb.ts_last_visit_lead_intent,
            qa.ts_last_tta_message_sent
        ) AS ts_last_visit_lead_intent,
        LEAST(fcm_cp.ts_first_contact_prospect, fhb.ts_first_contact_prospect) AS ts_first_contact_prospect,
        GREATEST(lcm_cp.ts_last_contact_prospect, lhb.ts_last_contact_prospect) AS ts_last_contact_prospect,
        fcl.ts_intent AS ts_first_classified_intent,
        lcl.ts_intent AS ts_last_classified_intent,
        qa.ts_first_visit_scheduling_event,
        qa.ts_last_visit_scheduling_event,
        qa.ts_first_tta_message_sent,
        qa.ts_last_tta_message_sent,
        qa.ts_first_booking_created AS ts_first_booking_created_5a,
        qa.ts_last_booking_created AS ts_last_booking_created_5a,
        qa.ts_first_visit_completed AS ts_first_visit_completed_5a,
        qa.ts_last_visit_completed AS ts_last_visit_completed_5a,
        fcm_bk.ts_first_booking_created AS ts_first_booking_created_cm,
        lcm_bk.ts_last_booking_created AS ts_last_booking_created_cm,
        fcm_v.ts_first_visit_completed AS ts_first_visit_completed_cm,
        lcm_v.ts_last_visit_completed AS ts_last_visit_completed_cm,
        LEAST(qa.ts_first_event, fcm_bk.ts_first_booking_created) AS ts_new_buyer_prospect,
        LEAST(qa.ts_first_booking_created, fcm_bk.ts_first_booking_created) AS ts_first_booking_created,
        GREATEST(qa.ts_last_booking_created, lcm_bk.ts_last_booking_created) AS ts_last_booking_created,
        LEAST(qa.ts_first_visit_completed, fcm_v.ts_first_visit_completed) AS ts_first_visit_completed,
        GREATEST(qa.ts_last_visit_completed, lcm_v.ts_last_visit_completed) AS ts_last_visit_completed,
        LEAST(qa.ts_first_offer_submitted, fcm_o.ts_first_offer_submitted) AS ts_first_offer_submitted,
        GREATEST(qa.ts_last_offer_submitted, lcm_o.ts_last_offer_submitted) AS ts_last_offer_submitted,
        LEAST(qa.ts_first_offer_accepted, fcm_ccv.ts_first_sale_agreement_signed) AS ts_first_offer_accepted,
        GREATEST(qa.ts_last_offer_accepted, lcm_ccv.ts_last_sale_agreement_signed) AS ts_last_offer_accepted,
        LEAST(qa.ts_first_sale_agreement_signed, fcm_ccv.ts_first_sale_agreement_signed) AS ts_first_sale_agreement_signed,
        GREATEST(qa.ts_last_sale_agreement_signed, lcm_ccv.ts_last_sale_agreement_signed) AS ts_last_sale_agreement_signed,
        fcm_ce.ts_first_combo_event_contact_prospect,
        lcm_ce.ts_last_combo_event_contact_prospect
    FROM
        unique_deduplicated_leads AS uu
    LEFT JOIN
        datalake_sale_lead_flows.quintoandar_lead_flow AS qa
            ON qa.id_user = uu.id_user
    LEFT JOIN
        first_hub_leads AS fhb
            ON fhb.id_lead = uu.id_lead
            AND fhb.rw_asc = 1
    LEFT JOIN 
        last_hub_leads AS lhb
            ON lhb.id_lead = uu.id_lead
            AND lhb.rw_desc = 1
    LEFT JOIN
        first_classified_leads AS fcl
            ON fcl.id_lead = uu.id_lead
            AND fcl.rw_asc = 1
    LEFT JOIN
        last_classified_leads AS lcl
            ON lcl.id_lead = uu.id_lead
            AND lcl.rw_desc = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_cp
            ON fcm_cp.id_lead = uu.id_lead
            AND fcm_cp.rw_asc_contact_prospect = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_cp
            ON lcm_cp.id_lead = uu.id_lead
            AND lcm_cp.rw_desc_contact_prospect = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_ce
            ON fcm_ce.id_lead = uu.id_lead
            AND fcm_ce.rw_asc_combo_event = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_ce
            ON lcm_ce.id_lead = uu.id_lead
            AND lcm_ce.rw_desc_combo_event = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_bk
            ON fcm_bk.id_lead = uu.id_lead
            AND fcm_bk.rw_asc_booking = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_bk
            ON lcm_bk.id_lead = uu.id_lead
            AND lcm_bk.rw_desc_booking = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_v
            ON fcm_v.id_lead = uu.id_lead
            AND fcm_v.rw_asc_visit = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_v
            ON lcm_v.id_lead = uu.id_lead
            AND lcm_v.rw_desc_visit = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_o
            ON fcm_o.id_lead = uu.id_lead
            AND fcm_o.rw_asc_offer = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_o
            ON lcm_o.id_lead = uu.id_lead
            AND lcm_o.rw_desc_offer = 1
    LEFT JOIN
        casa_mineira_leads AS fcm_ccv
            ON fcm_ccv.id_lead = uu.id_lead
            AND fcm_ccv.rw_asc_ccv = 1
    LEFT JOIN
        casa_mineira_leads AS lcm_ccv
            ON lcm_ccv.id_lead = uu.id_lead
            AND lcm_ccv.rw_desc_ccv = 1
)
SELECT
    id_lead,
    id_user,
    id_secretariat_client,
    id_classified_lead,
    id_visitor_hub_service,
    id_region_classified,
    id_region_contact_prospect,
    id_region_booking_cm,
    id_region_visit_intent,
    id_region_booking_5a,
    id_first_region,
    id_first_house,
    id_first_house_sale_agreement,
    first_touch,
    first_classified_partner,
    first_business_unit_region_intent_lead,
    last_business_unit_region_intent_lead,
    first_business_unit_region_new_buyer_prospect,
    first_city_booking_cm,
    first_city_contact_prospect,
    first_contact_prospect_origin,
    last_contact_prospect_origin,
    first_contact_prospect_media,
    last_contact_prospect_media,
    first_offer_flow,
    first_ccv_flow,
    first_offer_business_unit,
    first_ccv_business_unit,
    first_booking_creator_5a,
    has_secretariat_contact_created,
    has_booking_before_secretariat_contact,
    further_funnel_step,
    has_first_booking,
    has_tenant_rental_contract,
    is_ongoing_tenant_rental_contract,
    has_owner_rental_contract,
    has_rental_visit_intent,
    total_bookings_created_by_secretariat,
    total_bookings_created,
    total_bookings_canceled,
    total_visits_completed_by_secretariat,
    total_visits_completed,
    total_offer_submitted,
    total_sale_agreement_signed,
    DATEDIFF(DATE(ts_first_contact_prospect), DATE(ts_first_visit_lead_intent)) AS days_first_visit_intent_to_first_contact_prospect,
    DATEDIFF(DATE(ts_new_buyer_prospect), DATE(ts_first_visit_lead_intent)) AS days_first_visit_intent_to_new_buyer_prospect,
    DATEDIFF(DATE(ts_first_booking_created), DATE(ts_first_visit_lead_intent)) AS days_first_visit_intent_to_first_booking_created,
    DATEDIFF(DATE(ts_first_visit_completed), DATE(ts_first_visit_lead_intent)) AS days_first_visit_intent_to_first_visit_completed,
    DATEDIFF(DATE(ts_first_visit_completed), DATE(ts_first_booking_created)) AS days_first_booking_created_to_first_visit_completed,
    DATEDIFF(DATE(ts_first_offer_submitted), DATE(ts_first_booking_created)) AS days_first_booking_created_to_first_offer_submitted,
    DATEDIFF(DATE(ts_first_offer_accepted), DATE(ts_first_booking_created)) AS days_first_booking_created_to_first_offer_accepted,
    DATEDIFF(DATE(ts_first_sale_agreement_signed), DATE(ts_first_booking_created)) AS days_first_booking_created_to_first_sale_agreement_signed,
    DATEDIFF(DATE(ts_first_offer_submitted), DATE(ts_first_visit_completed)) AS days_first_visit_completed_to_first_offer_submitted,
    DATEDIFF(DATE(ts_first_offer_accepted), DATE(ts_first_visit_completed)) AS days_first_visit_completed_to_first_offer_accepted,
    DATEDIFF(DATE(ts_first_sale_agreement_signed), DATE(ts_first_visit_completed)) AS days_first_visit_completed_to_first_sale_agreement_signed,
    DATEDIFF(DATE(ts_first_offer_accepted), DATE(ts_first_offer_submitted)) AS days_first_offer_submitted_to_first_offer_accepted,
    DATEDIFF(DATE(ts_first_sale_agreement_signed), DATE(ts_first_offer_submitted)) AS days_first_offer_submitted_to_first_sale_agreement_signed,
    DATEDIFF(DATE(ts_first_sale_agreement_signed), DATE(ts_first_offer_accepted)) AS days_first_offer_accepted_to_first_sale_agreement_signed,
    ts_first_talk_to_secretariat,
    ts_last_talk_to_secretariat,
    ts_first_visit_lead_intent,
    ts_last_visit_lead_intent,
    ts_first_contact_prospect,
    ts_last_contact_prospect,
    ts_first_classified_intent,
    ts_last_classified_intent,
    ts_first_visit_scheduling_event,
    ts_last_visit_scheduling_event,
    ts_first_tta_message_sent,
    ts_last_tta_message_sent,
    ts_first_booking_created_5a,
    ts_last_booking_created_5a,
    ts_first_visit_completed_5a,
    ts_last_visit_completed_5a,
    ts_first_booking_created_cm,
    ts_last_booking_created_cm,
    ts_first_visit_completed_cm,
    ts_last_visit_completed_cm,
    ts_new_buyer_prospect,
    ts_first_booking_created,
    ts_last_booking_created,
    ts_first_visit_completed,
    ts_last_visit_completed,
    ts_first_offer_submitted,
    ts_last_offer_submitted,
    ts_first_offer_accepted,
    ts_last_offer_accepted,
    ts_first_sale_agreement_signed,
    ts_last_sale_agreement_signed,
    ts_first_combo_event_contact_prospect,
    ts_last_combo_event_contact_prospect
FROM
    final_base
WHERE
    first_touch IS NOT NULL