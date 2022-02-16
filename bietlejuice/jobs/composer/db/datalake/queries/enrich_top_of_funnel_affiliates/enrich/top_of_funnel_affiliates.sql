WITH events AS(
    SELECT
        DATE(ts_event) AS date,
        city,
        'Standard' AS affiliate_type,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) AS utm_source,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) AS utm_medium,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_content') AS STRING) AS utm_content,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_term') AS STRING) AS utm_term,
        COUNT(DISTINCT id_amplitude) AS unique_user
    FROM
        datalake_amplitude_clean.events
    WHERE
        event_type IN ('intro_page_viewed')
        AND id_app = 205027
        AND DATE(ts_event) = DATE('{year}-{month}-{day}')
        AND CAST(GET_JSON_OBJECT(event_properties, '$.uri') AS STRING) NOT LIKE '%https://mkt.quintoandar.com.br/indica-ai-porteiros/%'
    GROUP BY 1,2,3,4,5,6,7,8
)
SELECT
    events.city,
    events.affiliate_type,
    events.utm_source,
    events.utm_medium,
    events.utm_campaign,
    events.utm_content,
    events.utm_term,
    CASE
        WHEN tax.mkt_channel IS NULL THEN 'Other'
        ELSE 'Indica Ai - General'
    END AS mkt_origin,
    COALESCE(tax.mkt_channel, 'Not Mapped') as mkt_channel,
    COALESCE(tax.mkt_medium, 'Not Mapped') as mkt_medium,
    COALESCE(tax.mkt_source, 'Not Mapped') as mkt_source,
    SUM(unique_user) AS unique_user,
    events.date AS dt_event,
    year(events.date) AS year,
    month(events.date) AS month,
    day(events.date) AS day
FROM events
LEFT JOIN datalake_gsheets_clean.taxonomy_affiliates tax
    ON COALESCE(events.utm_source, '') = coalesce(tax.tracking_source, '')
    AND COALESCE(events.utm_medium, '') = coalesce(tax.tracking_medium, '')
    AND COALESCE(events.utm_campaign, '') = coalesce(tax.tracking_campaign, '')
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,13,14,15,16
