SELECT
    id_contact::BIGINT,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    GET_JSON_OBJECT(associations, '$.companies.results[0].id')::BIGINT AS id_company,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_first_touch_converting_campaign'), '') AS hs_analytics_first_touch_converting_campaign,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_last_touch_converting_campaign'), '') AS hs_analytics_last_touch_converting_campaign,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source'), '') AS hs_analytics_source,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source_data_1'), '') AS hs_analytics_source_data_1,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source_data_2'), '') AS hs_analytics_source_data_2,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_latest_source_data_1'), '') AS hs_latest_source_data_1,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_latest_source_data_2'), '') AS hs_latest_source_data_2,
    NULLIF(GET_JSON_OBJECT(properties, '$.first_conversion_event_name'), '') AS first_conversion_event_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.atuacao'), '') AS field_of_business,
    NULLIF(GET_JSON_OBJECT(properties, '$.cargos'), '') AS occupation,
    NULLIF(GET_JSON_OBJECT(properties, '$.address'), '') AS address,
    NULLIF(GET_JSON_OBJECT(properties, '$.city'), '') AS city,
    COALESCE(
        NULLIF(GET_JSON_OBJECT(properties, '$.estado'), ''), 
        NULLIF(GET_JSON_OBJECT(properties, '$.state'), '')
    ) AS state,
    NULLIF(GET_JSON_OBJECT(properties, '$.company'), '') AS company,
    NULLIF(GET_JSON_OBJECT(properties, '$.email'), '') AS email,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_domain'), '') AS hs_email_domain,
    NULLIF(GET_JSON_OBJECT(properties, '$.mobilephone'), '') AS mobile_phone,
    NULLIF(GET_JSON_OBJECT(properties, '$.phone'), '') AS phone,
    NULLIF(GET_JSON_OBJECT(properties, '$.website'), '') AS website,
    NULLIF(GET_JSON_OBJECT(properties, '$.firstname'), '') AS first_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.lastname'), '') AS last_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_marketable_status'), '') AS hs_marketable_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.lifecyclestage'), '') AS life_cycle_stage,
    NULLIF(GET_JSON_OBJECT(properties, '$.origem_do_lead__uso_restrito_'), '') AS lead_origin_restricted_use,
    NULLIF(GET_JSON_OBJECT(properties, '$.recent_conversion_event_name'), '') AS recent_conversion_event_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_lead_status'), '') AS lead_status,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.hs_lead_status'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            source_type:string,
            source_id:string,
            source_label:string,
            updated_by_user_id:string
        >>'
    ) AS lead_status_history,
    GET_JSON_OBJECT(properties, '$.num_conversion_events')::INT AS num_conversion_events,
    GET_JSON_OBJECT(properties, '$.num_associated_deals')::INT AS num_associated_deals,
    GET_JSON_OBJECT(properties, '$.hs_sequences_is_enrolled')::BOOLEAN AS is_enrolled_in_sequence,
    is_archived,
    GET_JSON_OBJECT(properties, '$.first_conversion_date')::TIMESTAMP AS ts_first_conversion,
    GET_JSON_OBJECT(properties, '$.notes_last_updated')::TIMESTAMP AS ts_notes_last_updated,
    GET_JSON_OBJECT(properties, '$.notes_next_activity_date')::TIMESTAMP AS ts_notes_next_activity,
    GET_JSON_OBJECT(properties, '$.closedate')::TIMESTAMP AS ts_closed,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.contact
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
