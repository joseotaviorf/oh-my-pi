SELECT
    IF(fvap.is_rent_agent IS TRUE, "RENT", "SALE") AS business_context,
    -- Agenda Allocation
    COALESCE(
      ROUND(
        SUM(fvap.total_hours_available_by_contract) / SUM(fvap.total_hours_allocation_available_by_schedule),
        2
      ),
      0
    ) AS ratio_schedule_engagement,
    COALESCE(
      ROUND(
        SUM(fvap.total_visit_booked) / SUM(fvap.total_hours_allocation_available_by_schedule) * 2,
        2
      ),
      0
    ) AS ratio_schedule_occupancy,
    -- Booking Performance
    COALESCE(ROUND(SUM(fvap.total_booking_stalled) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_stalled_bookings,
    COALESCE(ROUND(SUM(fvap.total_visit_booking_by_agent) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_bookings_by_agent,
    COALESCE(ROUND(SUM(fvap.total_booking_no_show_by_agent) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_no_show_bookings,
    COALESCE(ROUND(SUM(fvap.total_visit_cancellation_by_agent) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_visit_cancellations_by_agent,
    COALESCE(ROUND(SUM(fvap.total_booking_cancellation_by_agent) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_booking_cancellations_by_agent,
    -- Lead Conversion Metrics
    COALESCE(ROUND(SUM(fvap.total_visit_completed) / SUM(fvap.total_leads), 2), 0) AS ratio_leads_to_completed_visits,
    COALESCE(ROUND(SUM(fvap.total_offer_submitted) / SUM(fvap.total_leads), 2), 0) AS ratio_leads_to_offers_submitted,
    COALESCE(ROUND(SUM(fvap.total_visit_completed) / SUM(fvap.total_visit_booked), 2), 0) AS ratio_booked_to_completed_visits,
    COALESCE(ROUND(SUM(fvap.total_offer_submitted) / SUM(fvap.total_visit_completed), 2), 0) AS ratio_completed_visits_to_offers_submitted,
    COALESCE(ROUND(SUM(fvap.total_offer_approved) / SUM(fvap.total_offer_submitted), 2), 0) AS ratio_offers_submitted_to_approved,
    COALESCE(ROUND(SUM(fvap.total_document_sent) / SUM(fvap.total_offer_approved), 2), 0) AS ratio_offers_approved_to_documents_sent,
    COALESCE(ROUND(SUM(fvap.total_credit_approved) / SUM(fvap.total_document_sent), 2), 0) AS ratio_documents_sent_to_credit_approved,
    COALESCE(ROUND(SUM(fvap.total_contract_signed) / SUM(fvap.total_credit_approved), 2), 0) AS ratio_credit_approved_to_contract_signed,
    COALESCE(ROUND(SUM(fvap.total_leads_with_three_or_more_confirmed_visits) / SUM(fvap.total_leads), 2), 0) AS ratio_leads_3plus_confirmed_visits_same_agent,
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