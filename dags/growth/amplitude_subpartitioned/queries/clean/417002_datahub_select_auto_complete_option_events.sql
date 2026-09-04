SELECT
    id_amplitude,
    id_app,
    id_event,
    id_session,
    id_inserted,
    id_user,
    city,
    country,
    event_type,
    GET_JSON_OBJECT(event_properties, '$.entityType') AS entity_type,
    GET_JSON_OBJECT(event_properties, '$.entityUrn') AS entity_urn,
    GET_JSON_OBJECT(event_properties, '$.optionType') AS option_type,
    GET_JSON_OBJECT(event_properties, '$.apiVariant') AS api_variant,
    GET_JSON_OBJECT(event_properties, '$.showSearchBarAutocompleteRedesign') AS show_search_bar_autocomplete_redesign,
    ts_event,    
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'SelectAutoCompleteOption'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )