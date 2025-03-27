WITH agent_profile_activity AS (
    SELECT
        apa.id_agent,
        ad.date AS dt_reference
    FROM
        datalake_agent_accreditation.agent_profile_activity AS apa
    JOIN  
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN apa.dt_started AND apa.dt_ended
    WHERE
        apa.agent_profile = "Visita"
        AND ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
business_context_activity AS (
    SELECT
        XXHASH64(bca.id_agent, ad.date) AS id_agent_performance,
        bca.id_agent,
        bca.id_user,
        arm.major_region_code,
        bca.business_context,
        bca.total_active_days,
        DATEDIFF(ad.date, bca.dt_started) AS total_active_days_in_current_context,
        ad.date AS dt_reference,
        ad.year,
        ad.month,
        ad.day
    FROM
        datalake_agent_accreditation.business_context_activity AS bca
    JOIN  
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN bca.dt_started AND bca.dt_ended
    JOIN
        agent_profile_activity AS apa
            ON apa.id_agent = bca.id_agent
            AND apa.dt_reference = ad.date
    LEFT JOIN
        datalake_agent_accreditation.agent_major_region_code As arm
            ON arm.id_agent = bca.id_agent
            AND ad.date BETWEEN DATE(arm.ts_started) AND DATE(COALESCE(arm.ts_ended, '{load_end_date}'))
)
SELECT /*+ RANGE_JOIN(bca, 1500) */ 
    -- Agent accreditation data
    bca.id_agent_performance,
    bca.id_agent,
    bca.id_user,
    bca.major_region_code,
    bca.business_context,
    bca.total_active_days,
    bca.total_active_days_in_current_context,
    -- Agenda Allocation
    SUM(COALESCE(CAST(aha.is_allocation_available AS SMALLINT), 0)) AS total_hours_available_by_contract,
    SUM(COALESCE(aha.specific_allocated_slots, 0) / 4) AS total_hours_allocation_available_by_schedule,
    -- Supply
    COALESCE(COUNT(DISTINCT cfl.id_house), 0) AS total_supply_first_listing,
    -- Booking/Visit
    COALESCE(asp.total_visit_booked, 0) AS total_visit_booked,
    COALESCE(asp.total_visit_booking_by_agent, 0) AS total_visit_booking_by_agent,
    COALESCE(asp.total_visit_completed, 0) AS total_visit_completed,
    COALESCE(asp.total_booking_stalled, 0) AS total_booking_stalled,
    COALESCE(asp.total_booking_cancellation_by_agent, 0) AS total_booking_cancellation_by_agent,
    COALESCE(asp.total_visit_cancellation_by_agent, 0) AS total_visit_cancellation_by_agent,
    COALESCE(asp.total_booking_no_show_by_agent, 0) AS total_booking_no_show_by_agent,
    -- Sale/Rent Offer flow
    COALESCE(ofp.total_offer_submitted, 0) AS total_offer_submitted,
    COALESCE(ofp.total_offer_approved, 0) AS total_offer_approved,
    COALESCE(ofp.total_document_sent, 0) AS total_document_sent, 
    COALESCE(ofp.total_credit_approved, 0) AS total_credit_approved, 
    COALESCE(ofp.total_contract_signed, 0) AS total_contract_signed,
    COALESCE(ofp.total_proposal_evaluation_started, 0) AS total_proposal_evaluation_started, 
    -- Lead conversion (tenant/buyer)
    COALESCE(alp.total_leads, 0) AS total_leads,
    COALESCE(alp.total_leads_with_three_or_more_confirmed_visits, 0) AS total_leads_with_three_or_more_confirmed_visits,
    COALESCE(alp.total_lead_to_visit_booking, 0) AS total_lead_to_visit_booking,
    COALESCE(alp.total_lead_to_visit_booking_by_agent, 0) AS total_lead_to_visit_booking_by_agent,
    COALESCE(alp.total_lead_to_visit_completed, 0) AS total_lead_to_visit_completed,
    COALESCE(alp.total_lead_to_offer_submitted, 0) AS total_lead_to_offer_submitted,
    COALESCE(alp.total_lead_to_offer_approved, 0) AS total_lead_to_offer_approved,
    COALESCE(alp.total_lead_to_document_sent, 0) AS total_lead_to_document_sent, 
    COALESCE(alp.total_lead_to_credit_approved, 0) AS total_lead_to_credit_approved, 
    COALESCE(alp.total_lead_to_contract_signed, 0) AS total_lead_to_contract_signed,
    COALESCE(alp.total_lead_to_proposal_evaluation_started, 0) AS total_lead_to_proposal_evaluation_started, 
    COALESCE(alp.total_leads_to_contract_signed_cohort_7_days, 0) AS total_leads_to_contract_signed_cohort_7_days,
    -- Auxiliary columns for filtering data
    asp.id_agent_performance IS NOT NULL AS has_schedule_performance,
    ofp.id_agent_performance IS NOT NULL AS has_offer_performance,
    alp.id_agent_performance IS NOT NULL AS has_lead_performance,
    -- Dates
    bca.dt_reference,
    bca.year,
    bca.month,
    bca.day
FROM
    business_context_activity AS bca
LEFT JOIN
    datalake_visit_agent_performance.agent_schedules_performance AS asp
        ON asp.id_agent_performance = bca.id_agent_performance
LEFT JOIN
    datalake_visit_agent_performance.offer_flow_performance AS ofp
        ON ofp.id_agent_performance = bca.id_agent_performance
LEFT JOIN
    datalake_visit_agent_performance.agent_leads_performance AS alp
        ON alp.id_agent_performance = bca.id_agent_performance
LEFT JOIN
    datalake_agenda_allocation.agenda_hourly_allocations AS aha
        ON aha.id_agent = bca.id_agent
        AND aha.year = bca.year
        AND aha.month = bca.month
        AND aha.day = bca.day
LEFT JOIN
    datalake_tiers.ciq_first_listing AS cfl
        ON cfl.id_user = bca.id_user
        AND DATE(cfl.ts_first_listing) = bca.dt_reference
GROUP BY ALL
HAVING
    has_lead_performance IS TRUE
    OR has_offer_performance IS TRUE
    OR has_schedule_performance IS TRUE
    OR total_supply_first_listing <> 0
    OR total_hours_available_by_contract <> 0
    OR total_hours_allocation_available_by_schedule <> 0
