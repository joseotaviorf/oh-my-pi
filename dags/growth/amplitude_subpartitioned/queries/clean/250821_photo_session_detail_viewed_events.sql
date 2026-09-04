SELECT
    CAST(id_user AS BIGINT) AS id_user,
    CAST(get_json_object(event_properties, '$.photographerId') AS BIGINT) AS id_photographer,
    CAST(get_json_object(event_properties, '$.houseId') AS BIGINT) AS id_house,
    UPPER(get_json_object(event_properties, '$.businessContext[0]')) AS business_context,
    CAST(get_json_object(event_properties, '$.isEntryMethodsStepEnabled') AS BOOLEAN) AS is_entry_methods_step_enabled,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 250821
    AND event_type = 'photo_session_detail_viewed'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
