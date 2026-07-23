SELECT
    id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    GET_JSON_OBJECT(event_properties, '$.visit_status') AS visit_status,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_aluguel') AS BIGINT) AS rent_value,
    CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.valor_condominio'), GET_JSON_OBJECT(event_properties, '$.valor_condomínio')) AS BIGINT) AS condo_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_total') AS BIGINT) AS total_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_venda') AS BIGINT) AS sale_value,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 170698
    AND event_type = 'visit_fitting_requested_success_page_viewed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
