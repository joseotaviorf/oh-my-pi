SELECT
    target_type,
    business_type,
    rent_flow_origin,
    visits_booked,
    diff_vb,
    visits_completed,
    diff_vc,
    offers_submitted,
    diff_os,
    offers_accepted,
    diff_oa,
    evaluation_started,
    diff_es,
    evaluation_positive,
    diff_ep,
    documentation_sent,
    diff_ds,
    credit_approved,
    diff_ca,
    contracts_signed,
    diff_cs,
    dt_target,
    dt_snapshot,
    country_code,
    NOW() AS ts_load
FROM
    dw_rent_snapshot.coincident_events_time_variations_snapshot
WHERE
    year = YEAR(NOW())
    AND month = MONTH(NOW())
    AND day = DAY(NOW())
