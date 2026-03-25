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
    CAST(GET_JSON_OBJECT(event_properties, '$.activeFilterCount') AS INT) AS active_filter_count,
    CAST(GET_JSON_OBJECT(event_properties, '$.hiddenFilterCount') AS INT) AS hidden_filter_count,
    ts_event,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'SearchFiltersShowMoreEvent'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
