SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.gclid') AS up_gclid,
    GET_JSON_OBJECT(user_properties, '$.utm_source') AS up_utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') AS up_utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS up_utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_content') AS up_utm_content,
    GET_JSON_OBJECT(user_properties, '$.utm_term') AS up_utm_term,
    GET_JSON_OBJECT(user_properties, '$.platform') AS up_platform,
    GET_JSON_OBJECT(replace(user_properties, '[adjust]', '(adjust)'),
                    '$.(adjust) network') AS up_adjust_network,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') AS up_entrance_uri,
    GET_JSON_OBJECT(event_properties, '$.house_id') AS ep_house_id,
    GET_JSON_OBJECT(event_properties, '$.visit_code') AS ep_visit_code,
    LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS ep_business_context,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_days_available') AS INTEGER) AS nbr_days_available,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_hours_available') AS INTEGER) AS nbr_hours_available,
    CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.valor_aluguel'), GET_JSON_OBJECT(event_properties, '$["listing.valor_aluguel"]')) AS BIGINT) AS rent_value,
    CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.valor_condomínio'), GET_JSON_OBJECT(event_properties, '$["listing.valor_condominio"]')) AS BIGINT) AS condo_value,
    CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.valor_total'), GET_JSON_OBJECT(event_properties, '$["listing.valor_total"]')) AS BIGINT) AS total_value,
    CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.valor_venda'), GET_JSON_OBJECT(event_properties, '$["listing.valor_venda"]')) AS BIGINT) AS sale_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.scheduled_date') AS DATE) AS dt_schedule,
    COALESCE(GET_JSON_OBJECT(event_properties, '$.scheduled_hour_from'), GET_JSON_OBJECT(event_properties, '$.scheduled_hours_from')) AS hour_schedule_started,
    GET_JSON_OBJECT(event_properties, '$.scheduled_hour_to') AS hour_schedule_ended
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698' AND event_type = 'visit_schedule_confirmed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
