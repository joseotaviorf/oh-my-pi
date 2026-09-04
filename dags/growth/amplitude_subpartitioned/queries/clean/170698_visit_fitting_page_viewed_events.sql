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
    datalake_amplitude_events_clean.events
WHERE
    id_app = 170698
    AND event_type = 'visit_fitting_page_viewed'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
