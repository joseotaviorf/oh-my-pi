SELECT
    c.id_contact::BIGINT,
    GET_JSON_OBJECT(c.properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    GET_JSON_OBJECT(c.associations, '$.companies.results[0].id')::BIGINT AS id_company,
    u.id AS id_ebdb_user,
    FROM_JSON(
          GET_JSON_OBJECT(c.associations, '$.companies.results'),
          'array<struct<id: string, type: string>>'
    ) AS company_associations,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_analytics_first_touch_converting_campaign'), '') AS hs_analytics_first_touch_converting_campaign,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_analytics_last_touch_converting_campaign'), '') AS hs_analytics_last_touch_converting_campaign,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_analytics_source'), '') AS hs_analytics_source,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_analytics_source_data_1'), '') AS hs_analytics_source_data_1,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_analytics_source_data_2'), '') AS hs_analytics_source_data_2,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_latest_source_data_1'), '') AS hs_latest_source_data_1,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_latest_source_data_2'), '') AS hs_latest_source_data_2,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.first_conversion_event_name'), '') AS first_conversion_event_name,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.atuacao'), '') AS field_of_business,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.cargos'), '') AS occupation,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.address'), '') AS address,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.city'), '') AS city,
    COALESCE(
        NULLIF(GET_JSON_OBJECT(c.properties, '$.estado'), ''), 
        NULLIF(GET_JSON_OBJECT(c.properties, '$.state'), '')
    ) AS state,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.company'), '') AS company,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.email'), '') AS email,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_email_domain'), '') AS hs_email_domain,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_whatsapp_phone_number'), '') AS hs_whatsapp_phone_number,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.mobilephone'), '') AS mobile_phone,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.phone'), '') AS phone,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.website'), '') AS website,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.firstname'), '') AS first_name,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.lastname'), '') AS last_name,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_marketable_status'), '') AS hs_marketable_status,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.lifecyclestage'), '') AS life_cycle_stage,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.origem_do_lead__uso_restrito_'), '') AS lead_origin_restricted_use,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.recent_conversion_event_name'), '') AS recent_conversion_event_name,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.responsavel_pelo_nps'), '') AS nps_responsible,
    NULLIF(GET_JSON_OBJECT(c.properties, '$.hs_lead_status'), '') AS lead_status,
    FROM_JSON(
        GET_JSON_OBJECT(c.properties_with_history, '$.hs_lead_status'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS lead_status_history,
    GET_JSON_OBJECT(c.properties, '$.num_conversion_events')::INT AS num_conversion_events,
    GET_JSON_OBJECT(c.properties, '$.num_associated_deals')::INT AS num_associated_deals,
    GET_JSON_OBJECT(c.properties, '$.hs_sequences_is_enrolled')::BOOLEAN AS is_enrolled_in_sequence,
    CASE GET_JSON_OBJECT(c.properties, '$.demand_only__corretor_participou_da_live_de_onboarding_')
        WHEN 'Sim' THEN TRUE
        ELSE COALESCE(GET_JSON_OBJECT(c.properties, '$.demand_only__corretor_participou_da_live_de_onboarding_')::BOOLEAN, FALSE)
    END AS has_been_in_demand_only_onboarding_live,
    c.is_archived,
    GET_JSON_OBJECT(c.properties, '$.first_conversion_date')::TIMESTAMP AS ts_first_conversion,
    GET_JSON_OBJECT(c.properties, '$.notes_last_updated')::TIMESTAMP AS ts_notes_last_updated,
    GET_JSON_OBJECT(c.properties, '$.notes_next_activity_date')::TIMESTAMP AS ts_notes_next_activity,
    GET_JSON_OBJECT(c.properties, '$.closedate')::TIMESTAMP AS ts_closed,
    GET_JSON_OBJECT(c.properties, '$.demand_only__data_da_live')::TIMESTAMP AS ts_live_demand_only,
    c.ts_archived,
    c.ts_created,
    c.ts_updated,
    c.year,
    c.month,
    c.day
FROM
    datalake_hubspot_clean.contact AS c
LEFT JOIN
    datalake_ebdb_clean.`user` AS u
        ON TRIM(LOWER(NULLIF(GET_JSON_OBJECT(properties, '$.email'), ''))) = TRIM(LOWER(u.email))
WHERE
    c.year = {year}
    AND c.month = {month}
    AND c.day = {day}
QUALIFY
    ROW_NUMBER ()
    OVER (
        PARTITION BY
            c.year,
            c.month,
            c.day,
            c.id_contact
        ORDER BY
            u.id_agent NULLS LAST -- Prioritize agents in an eventual clash of emails
    )