SELECT
    id_visit_attempt_cycle AS sk_visit_attempt_cycle,
    id_visit_cycle AS sk_visit_cycle,
    id_visitor AS sk_visitor,
    id_house AS sk_house,
    MIN_BY(id_visit, ts_created) AS sk_first_visit,
    MAX_BY(id_visit, ts_created) AS sk_last_visit,
    MIN_BY(visit_request_channel, ts_created) AS first_visit_request_channel,
    MAX_BY(visit_request_channel, ts_created) AS last_visit_request_channel,
    MODE(business_context) AS business_context,
    MIN_BY(computed_status, ts_created) AS first_status,
    MODE(IF(computed_status <> 'DONE', computed_status, NULL)) AS mode_frustraded_status,
    MAX_BY(computed_status, ts_created) AS last_status,
    MIN_BY(cancellation_on_behalf_of, ts_created) FILTER (WHERE is_canceled) AS first_cancellation_on_behalf_of,
    MIN_BY(cancellation_reason, ts_created) FILTER (WHERE is_canceled) AS first_cancellation_reason,
    MIN_BY(unsuccessful_reason, ts_created) FILTER (WHERE is_unsuccessful) AS first_unsuccessful_reason,
    MAX_BY(cancellation_on_behalf_of, ts_created) FILTER (WHERE is_canceled) AS last_cancellation_on_behalf_of,
    MAX_BY(cancellation_reason, ts_created) FILTER (WHERE is_canceled) AS last_cancellation_reason,
    MAX_BY(unsuccessful_reason, ts_created) FILTER (WHERE is_unsuccessful) AS last_unsuccessful_reason,
    SUM(CAST(is_canceled_visit_contested_by_demand AS INTEGER)) >= 1 AS has_visits_canceled_contested,
    SUM(CAST(is_completed_visit_contested_by_demand AS INTEGER)) >= 1 AS has_visits_completed_contested,
    CASE
        WHEN MAX_BY(is_completed, ts_created) = TRUE THEN TRUE
        WHEN DATEDIFF(CURRENT_DATE, COALESCE(MAX_BY(ts_visit_canceled, ts_created), MAX_BY(ts_visit_unsuccessful, ts_created))) > 2 THEN TRUE
        ELSE FALSE
    END AS has_cycle_finished,
    1 AS num_cycles,
    COUNT(id_visit_attempt_cycle) AS num_visits,
    SUM(nbr_reschedule + 1) AS num_schedules,
    SUM(CAST(is_completed AS INTEGER)) AS num_visits_completed,
    SUM(CAST(is_canceled AS INTEGER)) AS num_visits_canceled,
    SUM(CAST(is_unsuccessful AS INTEGER)) AS num_visits_uncuccessful,
    MIN(ts_created) AS ts_first_visit_created,
    MAX(ts_created) AS ts_last_visit_created
FROM
    datalake_visit.visits
GROUP BY 1,2,3,4
