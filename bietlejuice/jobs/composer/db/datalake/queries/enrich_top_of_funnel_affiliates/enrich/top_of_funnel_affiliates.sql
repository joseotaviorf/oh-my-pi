WITH events AS(
    SELECT
        dt_event AS date,
        city,
        'Standard' AS affiliate_type,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        COUNT(DISTINCT id_amplitude) AS unique_user
    FROM
        datalake_amplitude_clean.205027_intro_page_viewed_events
    WHERE
       dt_event = DATE('{year}-{month}-{day}')
        AND ep_uri NOT LIKE '%https://mkt.quintoandar.com.br/indica-ai-porteiros/%'
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
