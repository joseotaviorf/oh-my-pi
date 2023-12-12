SELECT
    dd.date AS day,
    de.country_code,
    COUNT(DISTINCT IF(de.sk_event_type = 1, sk_event, NULL)) AS visit_booked,
    COUNT(DISTINCT IF(de.sk_event_type = 2, sk_event, NULL)) AS visit_completed,
    COUNT(DISTINCT IF(de.sk_event_type = 3, sk_event, NULL)) AS offer_submitted,
    COUNT(DISTINCT IF(de.sk_event_type = 4, sk_event, NULL)) AS offer_accepted,
    COUNT(DISTINCT IF(de.sk_event_type = 5, sk_event, NULL)) AS evaluation_started,
    COUNT(DISTINCT IF(de.sk_event_type = 6, sk_event, NULL)) AS evaluation_positive,
    COUNT(DISTINCT IF(de.sk_event_type = 7, sk_event, NULL)) AS document_sent,
    COUNT(DISTINCT IF(de.sk_event_type = 8, sk_event, NULL)) AS credit_approved,
    COUNT(DISTINCT IF(de.sk_event_type = 9, sk_event, NULL)) AS contract_signed,
    COUNT(DISTINCT IF(de.sk_event_type = 10, sk_event, NULL)) AS contract_created
FROM
    dw_rent.fact_rent_demand_events AS de
LEFT JOIN
    dw_rent.dim_owner_category AS dc
        ON dc.sk_owner_category = de.sk_owner_category
JOIN
    dw_public.dim_date AS dd
        ON dd.sk_date = de.sk_event_date
WHERE
    has_5_or_more_ongoing_houses = true
GROUP BY 1,2


