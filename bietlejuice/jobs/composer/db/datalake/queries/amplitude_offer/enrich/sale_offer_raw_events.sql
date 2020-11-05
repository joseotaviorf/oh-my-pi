WITH extracted_utms AS (
    SELECT
        id_user,
        id_app,
        TRIM(GET_JSON_OBJECT(event_properties, '$.house_id')) AS id_house,
        TRIM(GET_JSON_OBJECT(event_properties, '$.offer_id')) AS id_offer,
        GET_JSON_OBJECT(user_properties , '$.platform') AS app_type,
        GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
        GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
        GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
        GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
        GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
        ts_event
    FROM datalake_amplitude_clean.events evt
    WHERE  
        evt.event_type = 'sale_offer_form_accepted'
	    AND evt.id_app = 170698
)
SELECT
    id_user,
    id_app,
    id_house,
    id_offer,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    CASE
        WHEN (UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND UPPER(utm_campaign) NOT LIKE '%NON-BRANDED%'
            THEN 'Branded'
        ELSE 'Outro'
    END AS branded,
    COALESCE(((UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND LOWER(utm_campaign) NOT LIKE '%non-branded%'), FALSE) AS is_branded,
    ts_event
FROM extracted_utms