WITH extracted_utms AS (
    SELECT
        id_user,
        id_app,
        ep_id_house AS id_house,
        ep_id_agent AS id_agent,
        UPPER(ep_business_context) AS business_context,
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
        ep_message_content AS message_content,
        REPLACE(TRIM(SUBSTR(REGEXP_EXTRACT(REPLACE(REGEXP_REPLACE(ep_message_content,'\n',' '),'''',' '),'(?<=(([0-9]{{9}}))).*', 0),3)), 'omprar.', '') AS message_content_extracted,
        ts_event
    FROM
        datalake_amplitude_clean.170698_piloto_cw_message_sent_events
)
SELECT
    id_user,
    id_app,
    id_house,
    id_agent,
    business_context,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    branded,
    message_content,
    message_content_extracted,
    branded = 'Branded' AS is_branded,
    ts_event
FROM
    extracted_utms