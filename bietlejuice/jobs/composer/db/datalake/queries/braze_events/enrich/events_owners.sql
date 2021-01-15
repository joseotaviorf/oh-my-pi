SELECT
    GET_JSON_OBJECT(event_info,'$.id') AS id_event,
    GET_JSON_OBJECT(event_info,'$.dispatch_id') AS id_dispatch,
    GET_JSON_OBJECT(event_info,'$.user_id') AS id_user_braze,
    GET_JSON_OBJECT(event_info,'$.external_user_id') AS id_user,
    GET_JSON_OBJECT(event_info,'$.campaign_id') AS id_campaign,
    GET_JSON_OBJECT(event_info,'$.message_variation_id') AS id_variant_campaign,
    GET_JSON_OBJECT(event_info,'$.canvas_id') AS id_canvas,
    GET_JSON_OBJECT(event_info,'$.canvas_variation_id') AS id_variant_canvas,
    GET_JSON_OBJECT(event_info,'$.canvas_step_id') AS id_step_canvas,
    SPLIT(event_type, '\\.')[2] AS event_channel,
    event_type,
    CAST(FROM_UNIXTIME(CAST(GET_JSON_OBJECT(event_info,'$.time') AS INTEGER)) AS TIMESTAMP) AS ts_event      
FROM
    datalake_braze_clean.events_owners
WHERE
    event_type != 'users.behaviors.subscriptiongroup.StateChange'
