SELECT
    id_user,
    '170698' AS id_app,
    ep_id_house AS id_house,
    ep_id_firestore AS id_offer,
    up_app_type AS app_type,
    up_utm_source AS utm_source,
    up_utm_medium AS utm_medium,
    up_utm_campaign AS utm_campaign,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CASE
        WHEN (UPPER(up_utm_campaign) LIKE '%BRANDED%'
        OR UPPER(up_utm_campaign) LIKE '%INSTITUCIONAL%')
        AND UPPER(up_utm_campaign) NOT LIKE '%NON-BRANDED%'
            THEN 'Branded'
        ELSE 'Outro'
    END AS branded,
    COALESCE(((UPPER(up_utm_campaign) LIKE '%BRANDED%'
        OR UPPER(up_utm_campaign) LIKE '%INSTITUCIONAL%')
        AND LOWER(up_utm_campaign) NOT LIKE '%non-branded%'), FALSE) AS is_branded,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_sale_offer_form_accepted_events
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ep_id_firestore ORDER BY ts_event DESC) = 1
