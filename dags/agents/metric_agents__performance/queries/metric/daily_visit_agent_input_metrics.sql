SELECT
    fvap.sk_agent,
    IF(fvap.is_rent_agent IS TRUE, "RENT", "SALE") AS business_context,
    fvap.major_region_code,
    COALESCE(ROUND(fvap.total_hours_available_by_contract / fvap.total_hours_allocation_available_by_schedule, 2), 0) AS ratio_schedule_engagement,
    COALESCE(ROUND(fvap.total_visit_booked / fvap.total_hours_allocation_available_by_schedule * 2, 2), 0) AS ratio_schedule_occupancy,
    COALESCE(ROUND(fvap.total_booking_stalled / fvap.total_visit_booked, 2), 0) AS ratio_stalled_bookings,
    COALESCE(ROUND(fvap.total_visit_booking_by_agent / fvap.total_visit_booked, 2), 0) AS ratio_bookings_by_agent,
    COALESCE(ROUND(fvap.total_booking_no_show_by_agent / fvap.total_visit_booked, 2), 0) AS ratio_no_show_bookings,
    COALESCE(ROUND(fvap.total_visit_cancellation_by_agent / fvap.total_visit_booked, 2), 0) AS ratio_visit_cancellations_by_agent,
    COALESCE(ROUND(fvap.total_booking_cancellation_by_agent / fvap.total_visit_booked, 2), 0) AS ratio_booking_cancellations_by_agent,
    COALESCE(ROUND(fvap.total_visit_completed / fvap.total_leads, 2), 0) AS ratio_leads_to_completed_visits,
    COALESCE(ROUND(fvap.total_offer_submitted / fvap.total_leads, 2), 0) AS ratio_leads_to_offers_submitted,
    COALESCE(ROUND(fvap.total_visit_completed / fvap.total_visit_booked, 2), 0) AS ratio_booked_to_completed_visits,
    COALESCE(ROUND(fvap.total_offer_submitted / fvap.total_visit_completed, 2), 0) AS ratio_completed_visits_to_offers_submitted,
    COALESCE(ROUND(fvap.total_offer_approved / fvap.total_offer_submitted, 2), 0) AS ratio_offers_submitted_to_approved,
    COALESCE(ROUND(fvap.total_document_sent / fvap.total_offer_approved, 2), 0) AS ratio_offers_approved_to_documents_sent,
    COALESCE(ROUND(fvap.total_credit_approved / fvap.total_document_sent, 2), 0) AS ratio_documents_sent_to_credit_approved,
    COALESCE(ROUND(fvap.total_contract_signed / fvap.total_credit_approved, 2), 0) AS ratio_credit_approved_to_contract_signed,
    COALESCE(ROUND(fvap.total_leads_with_three_or_more_confirmed_visits / fvap.total_leads, 2), 0) AS ratio_leads_3plus_confirmed_visits,
    fvap.dt_reference,
    fvap.year,
    fvap.month,
    fvap.day
FROM
    dw_agent.fact_visit_agent_performance AS fvap
WHERE
    fvap.dt_reference = MAKE_DATE({year}, {month}, {day})
