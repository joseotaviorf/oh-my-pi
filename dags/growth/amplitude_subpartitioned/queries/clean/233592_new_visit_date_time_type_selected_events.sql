SELECT
    id_user,
    COALESCE(
        NULLIF(regexp_extract(
            GET_JSON_OBJECT(event_properties, '$.uri'),
            '(?:imovel%2F|imovel/|houseid=|house_id=)([0-9]+)',
            1
        ), ''),
        NULLIF(regexp_extract(
            GET_JSON_OBJECT(user_properties, '$.entrance_uri'),
            '(?:imovel%2F|imovel/)([0-9]+)',
            1
        ), ''),
        regexp_extract(
            GET_JSON_OBJECT(user_properties, '$.initial_entrance_uri'),
            '(?:imovel%2F|imovel/|houseid=|house_id=)([0-9]+)',
            1
        )
    ) AS id_house,
    GET_JSON_OBJECT(event_properties, '$.visitType') AS visit_type,
    GET_JSON_OBJECT(event_properties, '$.flow') AS flow,
    GET_JSON_OBJECT(user_properties, '$.isSaleAgent') AS is_sale_agent,
    GET_JSON_OBJECT(user_properties, '$.isRentAgent') AS is_rent_agent,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'new_visit_date_time_type_selected'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
