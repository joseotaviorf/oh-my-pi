-- USERS
WITH all_users AS (
    WITH user_aud AS (
        SELECT
            id_user,
            email,
            main_phone,
            ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY rev DESC) AS rw
        FROM 
            datalake_ebdb_clean.user_aud
        )
    SELECT
        id_user,
        LOWER(email) AS email,
        CASE
            WHEN RIGHT(main_phone,7) IN ('1111111','9999999','0000000','1212121','3456789','1234567','2222222','3333333','4444444','5555555','6666666','7777777','8888888','9999991')
                THEN NULL
            ELSE main_phone
        END AS phone_number
    FROM 
        user_aud
    WHERE 
        rw = 1
),

-- BOOKING EVENTS
booking AS (
    SELECT
        b.id_visitor AS id_user,
        b.id_house AS id_house,
        h.id_region,
        b.is_canceled,
        b.is_hub_flow,
        b.user_sale_booking_creator,
        bur.business_unit,
        b.ts_created AS ts_booking_created,
        ROW_NUMBER() OVER (PARTITION BY b.id_visitor ORDER BY b.ts_created) AS rw_asc,
        ROW_NUMBER() OVER (PARTITION BY b.id_visitor ORDER BY b.ts_created DESC) AS rw_desc
    FROM
        datalake_booking.booking AS b
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = b.id_house
    LEFT JOIN
        datalake_gsheets_clean.business_unit_region AS bur
            ON h.id_region = bur.id_region
            AND (DATE(b.ts_created) BETWEEN bur.dt_start AND COALESCE(bur.dt_end, date_sub(current_date(), 1)))
    WHERE
        b.visit_intent = 'SALE' 
        AND UPPER(b.type) = 'VISITA' 
),

first_booking AS (
    SELECT *
    FROM 
        booking
    WHERE 
        rw_asc =1
),

last_booking AS (
    SELECT *
    FROM 
        booking
    WHERE 
        rw_desc =1
),

booking_statistics AS (
    SELECT
        id_user,
        COUNT(*) AS total_bookings_created,
        COUNT(
            CASE
                WHEN is_canceled=true THEN 1
            END
        ) AS total_bookings_canceled,
        COUNT(
            CASE
                WHEN UPPER(user_sale_booking_creator) = 'SECRETARIA' THEN 1
            END
        ) AS total_bookings_created_by_secretariat
    FROM
        booking
    GROUP BY 
        id_user
),

-- VISIT EVENTS
visit AS (
    SELECT
        b.id_visitor AS id_user,
        b.ts_booking_utc AS ts_visit_completed,
        h.id_region,
        b.ts_created,
        ROW_NUMBER() OVER (PARTITION BY b.id_visitor ORDER BY b.ts_created) AS rw_asc,
        ROW_NUMBER() OVER (PARTITION BY b.id_visitor ORDER BY b.ts_created DESC) AS rw_desc
    FROM 
        datalake_booking.booking AS b
    LEFT JOIN
        datalake_ebdb_clean.house AS h
          ON h.id = b.id_house
    WHERE 
      IF
        (b.is_visit_completed, BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) > 0 
      AND 
        b.visit_intent = 'SALE'
      AND
        UPPER(b.type) = 'VISITA' 
),

first_visit AS (
    SELECT *
    FROM 
        visit
    WHERE 
        rw_asc =1
),

last_visit AS (
    SELECT *
    FROM 
        visit
    WHERE 
        rw_desc =1
),

visit_statistics AS (
    SELECT
        id_user,
        COUNT(
            CASE
                WHEN ts_visit_completed IS NOT NULL THEN 1
            END
        ) AS total_visits_completed
    FROM
        visit
    GROUP BY 
        id_user
),

-- OFFERS
offers AS (
    SELECT
        u.id_user,
        sf.id_house,
        sf.id_offer,
        sf.offer_flow,
        sf.business_unit,
        sf.id_region,
        sf.ts_offer_submitted,
        sf.dt_sale_agreement_signed,
        sf.dt_offer_accepted,
        ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY sf.ts_offer_submitted NULLS LAST) AS rw_offer_asc,
        ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY sf.ts_offer_submitted DESC NULLS LAST) AS rw_offer_desc,
        ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY sf.dt_sale_agreement_signed NULLS LAST) AS rw_ccv_asc,
        ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY sf.dt_sale_agreement_signed DESC NULLS LAST) AS rw_ccv_desc
    FROM 
        all_users AS u
    JOIN 
        datalake_offer.sale_offer AS sf
          ON sf.id_buyer = u.id_user
),

first_offer AS (
    SELECT *
    FROM 
        offers
    WHERE 
        rw_offer_asc =1
),

last_offer AS (
    SELECT *
    FROM 
        offers
    WHERE 
        rw_offer_desc =1
), 

first_ccv AS (
    SELECT *
    FROM 
        offers
    WHERE 
        rw_ccv_asc = 1
        AND dt_sale_agreement_signed IS NOT NULL
),

last_ccv AS (
    SELECT *
    FROM 
        offers
    WHERE 
        rw_ccv_desc = 1
        AND dt_sale_agreement_signed IS NOT NULL
),

offers_statistics AS (
    SELECT
        id_user,
        COUNT(
            CASE
                WHEN ts_offer_submitted IS NOT NULL THEN 1
            END
        ) AS total_offer_submitted,
        COUNT(
            CASE
                WHEN dt_sale_agreement_signed IS NOT NULL THEN 1
            END
        ) AS total_sale_agreement_signed
    FROM
        offers
    GROUP BY 
        id_user
),

-- SALES FLOW
sale_flow AS (
    SELECT
        sf.id_buyer,
        MIN(sf.ts_first_event) AS ts_first_sale_flow,
        MAX(sf.ts_first_event) AS ts_last_sale_flow
    FROM
        datalake_sale_flows.sale_flow AS sf
    JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = sf.id_house
    GROUP BY 1
),

-- FIRST EVENT
first_event AS (
    SELECT
        sf.id_buyer,
        MAX(fst.first_event) AS event,
        MIN(fst.ts_first_event) AS ts_first_event
    FROM
        sale_flow AS sf
    LEFT JOIN
        datalake_sale_flows.sale_flow AS fst
            ON fst.ts_first_event = sf.ts_first_sale_flow
            AND fst.id_buyer = sf.id_buyer
    GROUP BY 1
),

-- VISIT INTENT
visit_intent AS (
    SELECT
        e.id_user,
        e.ts_visit_intent,
        e.id_house,
        h.id_region,
        bur.business_unit,
        ROW_NUMBER() OVER (PARTITION BY e.id_user ORDER BY e.ts_visit_intent) AS rw_asc,
        ROW_NUMBER() OVER (PARTITION BY e.id_user ORDER BY e.ts_visit_intent DESC) AS rw_desc 
    FROM 
        datalake_amplitude_sale_visit_intent.amplitude_sale_visit_intent AS e
    LEFT JOIN 
        datalake_ebdb_clean.house AS h
            ON e.id_house = h.id
    LEFT JOIN
        datalake_gsheets_clean.business_unit_region AS bur
            ON h.id_region = bur.id_region
),

first_visit_intent AS (  
    SELECT
        id_user,
        id_house,
        id_region AS id_region_visit_intent,
        business_unit,
        ts_visit_intent AS ts_first_visit_scheduling_event
    FROM 
        visit_intent
    WHERE 
        rw_asc = 1
),

last_visit_intent AS (  
    SELECT
        id_user,
        id_house,
        id_region AS id_region_visit_intent,
        business_unit,
        ts_visit_intent AS ts_last_visit_scheduling_event
    FROM 
        visit_intent
    WHERE 
        rw_desc = 1
),

-- TENANT FLAGS
unique_buyer_prospects AS (
    SELECT
        id_buyer
    FROM
        datalake_sale_flows.sale_flow
    GROUP BY 1
),

flag_tenant AS (
    SELECT
        cp.id_user,
        MAX(
            CASE
                WHEN cp.type in ('Inquilino','Morador') THEN TRUE
                ELSE FALSE
            END) AS is_tenant,
        MAX(
            CASE
                WHEN cp.type in ('Proprietario') THEN TRUE
                ELSE FALSE
            END) AS is_contract_owner,
        MAX(
            CASE
                WHEN cp.type in ('Inquilino','Morador')
                    AND c.status = 'Ativo' THEN TRUE
                ELSE FALSE
            END) AS is_current_tenant
    FROM
        datalake_ebdb_clean.contract_person AS cp
    JOIN
        datalake_ebdb_contract.contract AS c
            ON c.id = cp.id_contract
    JOIN
        unique_buyer_prospects AS sf
            ON sf.id_buyer = cp.id_user
    GROUP BY 1
),

flag_tenant_prospect AS (
    SELECT
        sf.id_buyer,
        MAX(
            CASE
                WHEN b.visit_intent ='RENT' OR o.id_client IS NOT NULL THEN TRUE
                ELSE FALSE
            END) AS is_tenant_prospect
    FROM
        unique_buyer_prospects AS sf
    LEFT JOIN
        datalake_booking.booking AS b
            ON sf.id_buyer = b.id_visitor
    LEFT JOIN
        datalake_offer.offer AS o
            ON o.id_client = sf.id_buyer
    GROUP BY 1
)

SELECT 
    u.id_user,
    fb.id_region AS id_region_first_booking,
    lb.id_region AS id_region_last_booking,
    fvi.id_region_visit_intent AS id_region_first_visit_intent,
    lvi.id_region_visit_intent AS id_region_last_visit_intent,
    fo.id_region AS id_region_first_offer,
    lo.id_region AS id_region_last_offer,
    CASE LEAST(fvi.ts_first_visit_scheduling_event, fb.ts_booking_created, fo.ts_offer_submitted)
        WHEN fvi.ts_first_visit_scheduling_event THEN fvi.id_region_visit_intent
        WHEN fb.ts_booking_created THEN fb.id_region
        WHEN fo.ts_offer_submitted THEN fo.id_region
    END AS id_first_region,
    fc.id_house AS id_house_first_sale_agreement,
    CASE LEAST(fvi.ts_first_visit_scheduling_event, fb.ts_booking_created, fo.ts_offer_submitted)
        WHEN fvi.ts_first_visit_scheduling_event THEN fvi.id_house
        WHEN fb.ts_booking_created THEN fb.id_house
        WHEN fo.ts_offer_submitted THEN fo.id_house
    END AS id_first_house,
    fo.offer_flow AS first_offer_flow,
    fc.offer_flow AS first_ccv_flow,
    fo.business_unit AS first_offer_business_unit,
    fc.business_unit AS first_ccv_business_unit,
    fb.business_unit AS first_business_unit_region_new_buyer_prospect,
    lb.business_unit AS last_business_unit_region_new_buyer_prospect,
    fvi.business_unit AS first_business_unit_region_intent_lead,
    lvi.business_unit AS last_business_unit_region_intent_lead,
    fb.user_sale_booking_creator AS first_booking_creator_5a,
    u.email,
    u.phone_number,
    CASE
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lvi.ts_last_visit_scheduling_event
            THEN 'lead_submission'
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lv.ts_created
            THEN 'booking_created'
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lv.ts_visit_completed
            THEN 'visit_completed'
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lo.ts_offer_submitted
            THEN 'offer_submitted'
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lo.dt_offer_accepted
            THEN 'offer_accepted'
        WHEN GREATEST(lvi.ts_last_visit_scheduling_event, sf.ts_last_sale_flow, lv.ts_created, lv.ts_visit_completed,
              lo.ts_offer_submitted, lo.dt_offer_accepted, lc.dt_sale_agreement_signed) = lc.dt_sale_agreement_signed
            THEN 'sale_agreement_signed'
        WHEN GREATEST(lv.ts_created, lo.ts_offer_submitted) != sf.ts_last_sale_flow
              OR fe.event = 'talk_to_agent'
            THEN 'talk_to_agent'
    END AS last_event,
    CASE
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fvi.ts_first_visit_scheduling_event
            THEN 'lead_submission'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fc.dt_sale_agreement_signed
            THEN 'sale_agreement_signed'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fo.dt_offer_accepted
            THEN 'offer_accepted'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fo.ts_offer_submitted
            THEN 'offer_submitted'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fv.ts_visit_completed
            THEN 'visit_completed'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) = fv.ts_created
            THEN 'booking_created'
        WHEN COALESCE(fvi.ts_first_visit_scheduling_event, fc.dt_sale_agreement_signed, fo.dt_offer_accepted, fo.ts_offer_submitted,
                    fv.ts_visit_completed, fv.ts_created) IS NULL
            THEN 'talk_to_agent'
    END AS further_funnel_step,
    CASE 
        WHEN fb.ts_booking_created IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_first_booking,
    COALESCE(ft.is_tenant, FALSE) AS has_tenant_rental_contract,
    COALESCE(ft.is_current_tenant, FALSE) AS is_ongoing_tenant_rental_contract,
    COALESCE(ft.is_contract_owner, FALSE) AS has_owner_rental_contract,
    COALESCE(ftp.is_tenant_prospect, FALSE) AS has_rental_visit,
    COALESCE(bs.total_bookings_created, 0) AS total_bookings_created,
    COALESCE(bs.total_bookings_created_by_secretariat, 0) AS total_bookings_created_by_secretariat,
    COALESCE(bs.total_bookings_canceled, 0) AS total_bookings_canceled,
    COALESCE(vs.total_visits_completed, 0) AS total_visits_completed,
    COALESCE(os.total_offer_submitted, 0) AS total_offer_submitted,
    COALESCE(os.total_sale_agreement_signed, 0) AS total_sale_agreement_signed,
    fvi.ts_first_visit_scheduling_event,
    lvi.ts_last_visit_scheduling_event,
    fb.ts_booking_created AS ts_first_booking_created,
    lb.ts_booking_created AS ts_last_booking_created,
    fv.ts_visit_completed AS ts_first_visit_completed,
    lv.ts_visit_completed AS ts_last_visit_completed,
    fo.ts_offer_submitted AS ts_first_offer_submitted,
    lo.ts_offer_submitted AS ts_last_offer_submitted,
    fo.dt_offer_accepted AS ts_first_offer_accepted,
    lo.dt_offer_accepted AS ts_last_offer_accepted,
    fc.dt_sale_agreement_signed AS ts_first_sale_agreement_signed,
    lc.dt_sale_agreement_signed AS ts_last_sale_agreement_signed,
    fe.ts_first_event AS ts_first_event
FROM
    all_users AS u
LEFT JOIN 
    first_booking AS fb
        ON fb.id_user = u.id_user
LEFT JOIN 
    last_booking AS lb
        ON lb.id_user = u.id_user
LEFT JOIN
    booking_statistics AS bs
        ON bs.id_user = u.id_user
LEFT JOIN
    first_visit AS fv
        ON fv.id_user = u.id_user
LEFT JOIN
    last_visit AS lv
        ON lv.id_user = u.id_user
LEFT JOIN
    visit_statistics AS vs
        ON vs.id_user = u.id_user
LEFT JOIN
    first_offer AS fo
        ON fo.id_user = u.id_user
LEFT JOIN
    last_offer AS lo
        ON lo.id_user = u.id_user
LEFT JOIN
    first_ccv AS fc
        ON fc.id_user = u.id_user
LEFT JOIN
    last_ccv AS lc
        ON lc.id_user = u.id_user
LEFT JOIN
    offers_statistics AS os
        ON os.id_user = u.id_user
LEFT JOIN
    flag_tenant AS ft
        ON ft.id_user = u.id_user
LEFT JOIN
    flag_tenant_prospect AS ftp
        ON ftp.id_buyer = u.id_user
LEFT JOIN
    sale_flow AS sf
        ON sf.id_buyer = u.id_user
LEFT JOIN 
    first_event AS fe
        ON fe.id_buyer = u.id_user
LEFT JOIN 
    first_visit_intent AS fvi
        ON fvi.id_user = u.id_user
LEFT JOIN 
    last_visit_intent AS lvi
        ON lvi.id_user = u.id_user