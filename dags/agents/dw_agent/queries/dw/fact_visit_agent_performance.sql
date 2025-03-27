SELECT
    apds.id_agent_performance AS sk_agent_performance,
    apds.id_agent AS sk_agent,
    apds.major_region_code,
    apds.total_active_days,
    apds.total_active_days_in_current_context,
    -- Agenda Allocation
    apds.total_hours_available_by_contract,
    apds.total_hours_allocation_available_by_schedule,
    -- Supply
    apds.total_supply_first_listing,
    -- Booking/Visit
    apds.total_visit_booked,
    apds.total_visit_booking_by_agent,
    apds.total_visit_completed,
    apds.total_booking_stalled,
    apds.total_booking_cancellation_by_agent,
    apds.total_visit_cancellation_by_agent,
    apds.total_booking_no_show_by_agent,
    -- Sale/Rent Offer flow
    apds.total_offer_submitted,
    apds.total_offer_approved,
    apds.total_document_sent, 
    apds.total_credit_approved, 
    apds.total_contract_signed,
    apds.total_proposal_evaluation_started, 
    -- Lead conversion (tenant/buyer)
    apds.total_leads,
    apds.total_leads_with_three_or_more_confirmed_visits,
    apds.total_lead_to_visit_booking,
    apds.total_lead_to_visit_booking_by_agent,
    apds.total_lead_to_visit_completed,
    apds.total_lead_to_offer_submitted,
    apds.total_lead_to_offer_approved,
    apds.total_lead_to_document_sent, 
    apds.total_lead_to_credit_approved, 
    apds.total_lead_to_contract_signed,
    apds.total_lead_to_proposal_evaluation_started, 
    apds.total_leads_to_contract_signed_cohort_7_days,
    -- Auxiliary columns for filtering data
    apds.has_schedule_performance,
    apds.has_offer_performance,
    apds.has_lead_performance,
    COALESCE(apds.business_context = "RENT", FALSE) AS is_rent_agent,
    COALESCE(apds.business_context = "SALE", FALSE) AS is_sale_agent,
    -- Dates
    apds.dt_reference,
    apds.year,
    apds.month,
    apds.day
FROM
    datalake_visit_agent_performance.agent_performance_daily_summary AS apds
WHERE
    apds.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')