SELECT
    id_user,
    id_house,
    ts_event AS ts_visit_intent,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_visit_intent_clicked_events
WHERE
    id_user IS NOT NULL
    AND UPPER(business_context) = 'SALE'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
UNION ALL
SELECT
    id_user,
    id_house,
    ts_event AS ts_visit_intent,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_visit_schedule_clicked_events
WHERE
    id_user IS NOT NULL
    AND UPPER(business_context) = 'SALE'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
UNION ALL
SELECT
    id_user,
    ep_house_id AS id_house,
    ts_event AS ts_visit_intent,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_schedule_page_viewed_events
WHERE
    id_user IS NOT NULL
    AND UPPER(business_context) = 'SALE'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
UNION ALL
SELECT
    id_user,
    ep_house_id AS id_house,
    ts_event AS ts_visit_intent,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_visit_schedule_confirmed_events
WHERE
    id_user IS NOT NULL
    AND UPPER(ep_business_context) = 'SALE'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
