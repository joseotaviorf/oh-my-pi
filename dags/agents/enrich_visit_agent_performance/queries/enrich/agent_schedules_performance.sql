SELECT
    XXHASH64(ags.id_agent, DATE(ags.ts_created)) AS id_agent_performance,
    ags.id_agent,
    COALESCE(COUNT(DISTINCT ags.id_booking), 0) AS total_visit_booked,
    COALESCE(COUNT(DISTINCT ags.id_booking) FILTER (WHERE ags.is_visit_booking_by_agent IS TRUE), 0) AS total_visit_booking_by_agent,
    COALESCE(COUNT(DISTINCT ags.id_booking) FILTER (WHERE ags.is_visit_completed IS TRUE AND ags.is_visit_completed IS TRUE), 0) AS total_visit_completed,
    COALESCE(COUNT(DISTINCT ags.id_booking) FILTER (WHERE ags.is_booking_stalled IS TRUE), 0) AS total_booking_stalled,
    COALESCE(COUNT(DISTINCT ags.id_booking) FILTER (WHERE ags.is_booking_cancellation_by_agent IS TRUE), 0) AS total_booking_cancellation_by_agent,
    COALESCE(COUNT(DISTINCT ags.id_visit) FILTER (WHERE ags.is_visit_cancellation_by_agent IS TRUE), 0) AS total_visit_cancellation_by_agent,
    COALESCE(COUNT(DISTINCT ags.id_booking) FILTER (WHERE ags.is_visit_cancellation_by_agent IS TRUE), 0) AS total_booking_no_show_by_agent,
    DATE(ags.ts_created) AS dt_reference,
    ags.year,
    ags.month,
    ags.day
FROM
    datalake_visit_agent_performance.agent_schedules AS ags
WHERE
    ags.has_direct_first_touchpoint IS FALSE
    AND DATE(ags.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY ALL