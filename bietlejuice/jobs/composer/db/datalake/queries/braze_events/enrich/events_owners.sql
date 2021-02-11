SELECT
    GET_JSON_OBJECT(event_info,'$.id') AS id_event,
    GET_JSON_OBJECT(event_info,'$.dispatch_id') AS id_dispatch,
    MD5(ENCODE(CONCAT(
                COALESCE(
                    GET_JSON_OBJECT(event_info,'$.dispatch_id'),
                    CASE
                        WHEN event_type = 'users.messages.webhook.Send'
                        THEN CAST(FROM_UNIXTIME(CAST(GET_JSON_OBJECT(event_info,'$.time') AS INTEGER)) AS TIMESTAMP)
                    END),
                GET_JSON_OBJECT(event_info,'$.user_id')),
        'utf-8')) AS id_user_dispatch,
    GET_JSON_OBJECT(event_info,'$.user_id') AS id_user_braze,
    GET_JSON_OBJECT(event_info,'$.external_user_id') AS id_user,
    GET_JSON_OBJECT(event_info,'$.campaign_id') AS id_campaign,
    GET_JSON_OBJECT(event_info,'$.message_variation_id') AS id_variant_campaign,
    GET_JSON_OBJECT(event_info,'$.canvas_id') AS id_canvas,
    GET_JSON_OBJECT(event_info,'$.canvas_variation_id') AS id_variant_canvas,
    GET_JSON_OBJECT(event_info,'$.canvas_step_id') AS id_step_canvas,  
    IF(SIZE(SPLIT(event_type, '\\.'))>3,LOWER(SPLIT(event_type, '\\.')[2]),NULL) AS event_channel,
    LOWER(REVERSE(SPLIT(event_type, '\\.'))[0]) AS event_action,
    event_type,
    CAST(FROM_UNIXTIME(CAST(GET_JSON_OBJECT(event_info,'$.time') AS INTEGER)) AS TIMESTAMP) AS ts_event,
    year,
    month,
    day
FROM
    datalake_braze_clean.events_owners
WHERE
    event_type NOT IN(
        'users.behaviors.subscriptiongroup.StateChange',
        'users.behaviors.Uninstall',
        'users.campaigns.Conversion',
        'users.campaigns.EnrollInControl',
        'users.canvas.Conversion',
        'users.canvas.Entry'
    )
    AND year = {year}
    AND month = {month}
    AND day = {day}
