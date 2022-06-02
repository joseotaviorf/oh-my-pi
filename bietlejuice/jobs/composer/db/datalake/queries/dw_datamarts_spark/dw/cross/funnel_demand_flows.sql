-- FIRSTLY WE ORGANIZE THE STRUCTURES
-- (1) BOOKINGS, (2) TALK TO AGENT and (3) OFFER

-- BOOKINGS
-- FIRSTLY WE ORGANIZE THE STRUCTURES
-- (1) BOOKINGS, (2) TALK TO AGENT and (3) OFFER

-- BOOKINGS
WITH fb AS (
    SELECT 
        rf.sk_rent_flow,
        rf.sk_house_listing,
    	rf.sk_client,
    	COUNT(DISTINCT rf.sk_booking) AS visits_booked,
    	COUNT(DISTINCT CASE WHEN rf.flg_visit_completed THEN rf.sk_booking END) AS visits_completed,
        MIN(db.dt_created) AS dt_first_visit_booked,
        MIN(CASE WHEN rf.flg_visit_completed THEN db.dt_created END) AS dt_first_visit_completed,
        MIN(CASE WHEN fup.visit_type='PRESENTIAL' OR (rf.flg_visit_completed AND fup.visit_type<>'VIDEO') THEN db.dt_created END) AS dt_first_presential_visit,
        COUNT(DISTINCT CASE WHEN rf.sk_booking > 0 THEN rf.sk_booking END) AS nbr_visit_booked,
        COUNT(DISTINCT CASE WHEN rf.flg_visit_completed THEN rf.sk_booking END) AS nbr_visit_completed,
        COUNT(DISTINCT CASE WHEN fup.visit_type = 'PRESENTIAL' OR (rf.flg_visit_completed AND fup.visit_type<>'VIDEO') THEN rf.sk_booking END) AS nbr_presential_visit
    FROM 
        dw_public.fact_listing_rent_flows AS rf
    JOIN 
        dw_public.dim_booking AS db
            ON rf.sk_booking = db.sk_booking
    LEFT JOIN 
        datalake_ebdb_clean.booking 
            ON booking.id = rf.sk_booking
    LEFT JOIN 
        datalake_ebdb_clean.follow_up_details AS fup
            ON fup.id = booking.id_fup_details 
    LEFT JOIN 
        dw_public.dim_tenant_booking_review AS tbr
            ON rf.sk_tenant_booking_review = tbr.sk_tenant_booking_review
    WHERE 
        rf.sk_booking > 0
    GROUP BY 1,2,3
),

-- (2) TALK TO AGENT
-- Users who started attendance (PS: this is temporary until we have product dev. AND a dim_ model)
ft AS(
    SELECT 
        sk_house_listing,
        tenant_id,
        MIN(first_message_ts)::TIMESTAMP AS dt_tta,
        SUM(msg_sent) AS msg_sent
    FROM 
        dw_datamarts_cross.talk_to_agent
    GROUP BY 1,2
),

--OFFERS
fo AS (
    SELECT DISTINCT 
        rf.sk_offer,
        rf.sk_client,
        rf.sk_house_listing,
        o.type,
        o.dt_first_sent AS dt_offer,
        CASE
            WHEN visits_completed > 0 
                AND dt_first_visit_booked <= o.dt_first_sent THEN 'OS_VC'
            WHEN visits_completed = 0 
                AND dt_first_visit_booked <= o.dt_first_sent THEN 'OS_WITH_VB'
            WHEN visits_completed IS NULL THEN 'OS_DIRECT'
            WHEN visits_completed = 0 
                AND dt_first_visit_booked > o.dt_first_sent THEN 'OS_DIRECT_VB_LATER'
            WHEN visits_completed > 0 
                AND dt_first_visit_booked > o.dt_first_sent THEN 'OS_DIRECT_VC_LATER'
        END	AS offer_type,
        ((visits_completed IS NULL) 
            OR (dt_first_visit_booked > o.dt_first_sent)) AS direct_offer
    FROM 
        dw_public.fact_listing_rent_flows AS rf
    JOIN 
        dw_public.dim_offer AS o
            ON rf.sk_offer = o.sk_offer
    LEFT JOIN 
        fb
            ON (fb.sk_client=rf.sk_client 
            AND fb.sk_house_listing=rf.sk_house_listing)
    WHERE 
        rf.sk_offer > 0
    GROUP BY 1,2,3,4,5,visits_completed,dt_first_visit_booked,o.dt_first_sent
),

-- NOW WE CLASSIFY THE RENTFLOWS
-- Criterea: flow (highest touchpoint), first_touchpoint (WHERE it started), had_[do,tta,pv] (WHERE it passed)
flows_class AS (
    SELECT
        r.sk_rent_flow,
        r.sk_house_listing,
        r.sk_client,
        LEAST(MIN(fo.dt_offer), MIN(ft.dt_tta), MIN(fb.dt_first_visit_booked)) AS first_ts,
        --flow highest intent flow
        CASE  
            WHEN MAX(CASE WHEN fb.visits_booked > 0 THEN 1 ELSE 0 END)> 0 THEN 'VISIT'
            WHEN MAX(CASE WHEN msg_sent > 0 THEN 1 ELSE 0 END) > 0 THEN 'TTA'
            WHEN MAX(CASE WHEN fo.sk_offer > 0 THEN 1 ELSE 0 END) > 0 THEN 'DIRECT'
            ELSE 'UNKNOWN' 
        END AS funnel_flow, 
        CASE
            WHEN MIN(fb.dt_first_visit_booked) < LEAST(MIN(ft.dt_tta), MIN(fo.dt_offer), CURRENT_TIMESTAMP) THEN 'VISIT'
            WHEN MIN(ft.dt_tta) < LEAST(MIN(fb.dt_first_visit_booked), MIN(fo.dt_offer), CURRENT_TIMESTAMP) THEN 'TTA'
            WHEN MIN(fo.dt_offer) < LEAST(MIN(ft.dt_tta),MIN(fb.dt_first_visit_booked),CURRENT_TIMESTAMP) THEN 'DIRECT'
            ELSE 'UNKNOWN' 
        END AS funnel_first_touchpoint,
        BOOL_OR(CASE WHEN fo.direct_offer = true THEN true ELSE false END) AS had_flow_direct,
        BOOL_OR(CASE WHEN ft.msg_sent > 0 THEN true ELSE false END) AS had_flow_tta,
        BOOL_OR(CASE WHEN fb.visits_booked > 0 THEN true ELSE false END) AS had_flow_visit,
        COUNT(DISTINCT CASE WHEN fo.direct_offer THEN fo.sk_offer END) AS nbr_direct_offer,
        COUNT(DISTINCT CASE WHEN fo.sk_offer > 0 THEN fo.sk_offer END) AS nbr_offer,
        COUNT(DISTINCT CASE WHEN ft.dt_tta IS NOT NULL THEN ft.dt_tta END) AS nbr_tta,
        MIN(fb.nbr_visit_booked) AS nbr_visit_booked,
        MIN(fb.nbr_visit_completed) AS nbr_visit_completed,
        MIN(fb.nbr_presential_visit) AS nbr_presential_visit,
        MIN(CASE WHEN fo.direct_offer THEN fo.dt_offer END) AS dt_first_direct_offer,
        MIN(fo.dt_offer) AS dt_first_offer,
        MIN(ft.dt_tta) AS dt_first_tta,
        MIN(fb.dt_first_visit_booked) AS dt_first_visit_booked,
        MIN(dt_first_visit_completed) AS dt_first_visit_completed,
        MIN(dt_first_presential_visit) AS dt_first_presential_visit,
        MIN(CASE WHEN fo.direct_offer THEN fo.dt_offer END) AS dt_flow_direct,
        MIN(CASE WHEN msg_sent > 0 THEN ft.dt_tta END) AS dt_flow_tta,
        MIN(fb.dt_first_visit_booked) AS dt_flow_visit,
        BOOL_OR(sk_contract_signed_date > 0) AS cs,
        COUNT(1) AS lines
    FROM 
        dw_public.fact_listing_rent_flows AS r
    LEFT JOIN 
        fo
            ON fo.sk_client = r.sk_client
            AND fo.sk_house_listing = r.sk_house_listing
    LEFT JOIN 
        ft
            ON ft.tenant_id = r.sk_client
            AND ft.sk_house_listing = r.sk_house_listing
    LEFT JOIN 
        fb
            ON fb.sk_client = r.sk_client
            AND fb.sk_house_listing = r.sk_house_listing
    GROUP BY 1,2,3
)
SELECT 
    sk_rent_flow,
    sk_house_listing,
    sk_client,
    first_ts,
    funnel_flow,
    funnel_first_touchpoint,
    had_flow_direct,
    had_flow_tta,
    had_flow_visit,
    nbr_direct_offer,
    nbr_tta,
    nbr_offer,
    nbr_visit_booked,
    nbr_visit_completed,
    nbr_presential_visit,
    dt_first_direct_offer,
    dt_first_offer,
    dt_first_tta,
    dt_first_visit_booked,
    dt_first_visit_completed,
    dt_first_presential_visit,
    --Sankey Flows
    CAST(
        CASE
            WHEN dt_flow_direct IS NOT NULL 
                AND ((dt_flow_tta IS NULL AND dt_flow_visit IS NULL) 
                    OR (dt_flow_direct < (LEAST(dt_flow_visit, dt_flow_tta)))) THEN '1'
            WHEN dt_flow_tta IS NOT NULL 
                AND ((dt_flow_direct IS NULL AND dt_flow_visit IS NULL) 
                    OR (dt_flow_tta < (LEAST(dt_flow_direct, dt_flow_visit)))) THEN '2'
            WHEN dt_flow_visit IS NOT NULL 
                AND ((dt_flow_tta IS NULL AND dt_flow_direct IS NULL)
                    OR (dt_flow_visit < (LEAST(dt_flow_tta, dt_flow_direct)))) THEN '3'
            ELSE '-'
        END AS STRING)
    ||
    CAST(
        CASE
            WHEN (dt_flow_direct > dt_flow_tta) 
                AND (dt_flow_direct < dt_flow_visit OR dt_flow_visit IS NULL)  THEN '1'
            WHEN (dt_flow_direct > dt_flow_visit) 
                AND (dt_flow_direct < dt_flow_tta OR dt_flow_tta IS NULL)  THEN '1'
            WHEN (dt_flow_tta > dt_flow_direct) 
                AND (dt_flow_tta < dt_flow_visit OR dt_flow_visit IS NULL)  THEN '2'
            WHEN (dt_flow_tta > dt_flow_visit) 
                AND (dt_flow_tta < dt_flow_direct OR dt_flow_direct IS NULL)  THEN '2'
            WHEN (dt_flow_visit > dt_flow_direct) 
                AND (dt_flow_visit < dt_flow_tta OR dt_flow_tta IS NULL)  THEN '3'
            WHEN (dt_flow_visit > dt_flow_tta) 
                AND (dt_flow_visit < dt_flow_direct OR dt_flow_direct IS NULL)  THEN '3'
            ELSE '-'
        END AS STRING)
    ||
    CAST(
        CASE
            WHEN dt_flow_direct > greatest(dt_flow_tta,dt_flow_visit) 
                AND dt_flow_tta IS NOT NULL 
                AND dt_flow_visit IS NOT NULL THEN '1'
            WHEN dt_flow_tta > greatest(dt_flow_visit,dt_flow_direct) 
                AND dt_flow_visit IS NOT NULL 
                AND dt_flow_direct IS NOT NULL THEN '2'
            WHEN dt_flow_visit > greatest(dt_flow_tta,dt_flow_direct) 
                AND dt_flow_tta IS NOT NULL 
                AND dt_flow_direct IS NOT NULL THEN '3'
            ELSE '-'
        END AS STRING)
    AS sankey_flows,

    --Combined Flows
    CASE 
        WHEN had_flow_visit = 0 
            AND had_flow_direct = 1 
            AND had_flow_tta = 0 THEN '(1) ONLY DIRECT OFFER'
        WHEN had_flow_visit = 0 
            AND had_flow_direct = 0 
            AND had_flow_tta = 1 THEN '(2) ONLY TALK TO AGENT'
        WHEN had_flow_visit = 1 
            AND had_flow_direct = 0 
            AND had_flow_tta = 0 THEN '(3) ONLY VISIT'
        WHEN had_flow_visit = 0 
            AND had_flow_direct = 1 
            AND had_flow_tta = 1 THEN '(1) DIRECT OFFER + (2) TALK TO AGENT'
        WHEN had_flow_visit = 1
            AND had_flow_direct = 1 
            AND had_flow_tta = 0 THEN '(1) DIRECT OFFER + (3) VISIT'
        WHEN had_flow_visit = 1 
            AND had_flow_direct = 0 
            AND had_flow_tta = 1 THEN '(2) TALK TO AGENT + (3) VISIT'
        WHEN had_flow_visit = 1 
            AND had_flow_direct = 1 
            AND had_flow_tta = 1 THEN '(1) DO + (2) TTA + (3) VISIT'
        WHEN had_flow_visit = 0 
            AND had_flow_direct = 0 
            AND had_flow_tta = 0 THEN 'NO ONE'
        ELSE 'UNK' 
    END AS flow_type,
    --Sankey Journey
    CAST(
        CASE
            WHEN dt_first_offer IS NOT NULL 
                AND ((dt_first_tta IS NULL AND dt_first_visit_completed IS NULL) 
                OR (dt_first_offer < (LEAST(dt_first_visit_completed, dt_first_tta)))) THEN '1'
            WHEN dt_first_tta IS NOT NULL 
                AND ((dt_first_offer IS NULL 
                AND dt_first_visit_completed IS NULL) 
                OR (dt_first_tta < (LEAST(dt_first_offer, dt_first_visit_completed)))) THEN '2'
            WHEN dt_first_visit_completed IS NOT NULL 
                AND ((dt_first_tta IS NULL AND dt_first_offer IS NULL) 
                OR (dt_first_visit_completed < (LEAST(dt_first_tta, dt_first_offer)))) THEN '3'
            ELSE '-'
        END AS STRING)
    ||
    CAST(
        CASE
            WHEN (dt_first_offer > dt_first_tta) 
                AND (dt_first_offer < dt_first_visit_completed OR dt_first_visit_completed IS NULL) THEN '1'
            WHEN (dt_first_offer > dt_first_visit_completed) 
                AND (dt_first_offer < dt_first_tta OR dt_first_tta IS NULL) THEN '1'
            WHEN (dt_first_tta > dt_first_offer) 
                AND (dt_first_tta < dt_first_visit_completed OR dt_first_visit_completed IS NULL) THEN '2'
            WHEN (dt_first_tta > dt_first_visit_completed) 
                AND (dt_first_tta < dt_first_offer OR dt_first_offer IS NULL) THEN '2'
            WHEN (dt_first_visit_completed > dt_first_offer) 
                AND (dt_first_visit_completed < dt_first_tta OR dt_first_tta IS NULL) THEN '3'
            WHEN (dt_first_visit_completed > dt_first_tta) 
                AND (dt_first_visit_completed < dt_first_offer OR dt_first_offer IS NULL) THEN '3'
            ELSE '-'
        END AS STRING)
    ||
    CAST(
        CASE
            WHEN dt_first_offer > greatest(dt_first_tta,dt_first_visit_completed) 
                AND dt_first_tta IS NOT NULL 
                AND dt_first_visit_completed IS NOT NULL THEN '1'
            WHEN dt_first_tta > greatest(dt_first_visit_completed,dt_first_offer) 
                AND dt_first_visit_completed IS NOT NULL 
                AND dt_first_offer IS NOT NULL THEN '2'
            WHEN dt_first_visit_completed > greatest(dt_first_tta,dt_first_offer) 
                AND dt_first_tta IS NOT NULL 
                AND dt_first_offer IS NOT NULL THEN '3'
            ELSE '-'
        END AS STRING)
    AS sankey_journey,
    cs,
    lines
FROM flows_class