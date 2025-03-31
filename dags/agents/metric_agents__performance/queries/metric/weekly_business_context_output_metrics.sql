SELECT
    IF(fvap.is_rent_agent IS TRUE, "RENT", "SALE") AS business_context,
    -- Agenda Allocation
    ROUND(AVG(fvap.total_hours_available_by_contract), 2) AS average_hours_available_by_contract,
    ROUND(AVG(fvap.total_hours_allocation_available_by_schedule), 2) AS average_hours_allocation_available_by_schedule,
    -- Supply
    SUM(fvap.total_supply_first_listing) AS total_supply_first_listing,
    -- Booking/Visit
    SUM(fvap.total_visit_booked) AS total_visit_booked,
    SUM(fvap.total_visit_booking_by_agent) AS total_visit_booking_by_agent,
    SUM(fvap.total_visit_completed) AS total_visit_completed,
    SUM(fvap.total_booking_stalled) AS total_booking_stalled,
    SUM(fvap.total_booking_cancellation_by_agent) AS total_booking_cancellation_by_agent,
    SUM(fvap.total_visit_cancellation_by_agent) AS total_visit_cancellation_by_agent,
    SUM(fvap.total_booking_no_show_by_agent) AS total_booking_no_show_by_agent,
    -- Sale/Rent Offer flow
    SUM(fvap.total_offer_submitted) AS total_offer_submitted,
    SUM(fvap.total_offer_approved) AS total_offer_approved,
    SUM(fvap.total_document_sent) AS total_document_sent, 
    SUM(fvap.total_credit_approved) AS total_credit_approved, 
    SUM(fvap.total_contract_signed) AS total_contract_signed,
    SUM(fvap.total_proposal_evaluation_started) AS total_proposal_evaluation_started, 
    -- Lead conversion (tenant/buyer)
    SUM(fvap.total_leads) AS total_leads,
    SUM(fvap.total_leads_with_three_or_more_confirmed_visits) AS total_leads_3plus_confirmed_visits_same_agent,
    SUM(fvap.total_lead_to_visit_booking) AS total_lead_to_visit_booking,
    SUM(fvap.total_lead_to_visit_booking_by_agent) AS total_lead_to_visit_booking_by_agent,
    SUM(fvap.total_lead_to_visit_completed) AS total_lead_to_visit_completed,
    SUM(fvap.total_lead_to_offer_submitted) AS total_lead_to_offer_submitted,
    SUM(fvap.total_lead_to_offer_approved) AS total_lead_to_offer_approved,
    SUM(fvap.total_lead_to_document_sent) AS total_lead_to_document_sent, 
    SUM(fvap.total_lead_to_credit_approved) AS total_lead_to_credit_approved, 
    SUM(fvap.total_lead_to_contract_signed) AS total_lead_to_contract_signed,
    SUM(fvap.total_lead_to_proposal_evaluation_started) AS total_lead_to_proposal_evaluation_started, 
    SUM(fvap.total_leads_to_contract_signed_cohort_7_days) AS total_leads_to_contract_signed_cohort_7_days,
    -- Dates
    DATE_TRUNC('WEEK', fvap.dt_reference) AS dt_week_start,
    YEAR(DATE_TRUNC('WEEK', fvap.dt_reference)) AS year,
    MONTH(DATE_TRUNC('WEEK', fvap.dt_reference)) AS month,
    DAY(DATE_TRUNC('WEEK', fvap.dt_reference)) AS day
FROM
    dw_agent.fact_visit_agent_performance AS fvap
WHERE
    DATE_TRUNC('WEEK', fvap.dt_reference) = DATE_TRUNC('WEEK', MAKE_DATE({year}, {month}, {day}))
GROUP BY ALL