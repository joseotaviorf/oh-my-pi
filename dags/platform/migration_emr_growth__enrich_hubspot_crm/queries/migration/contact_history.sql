SELECT
  id_contact,
  id_hubspot_owner,
  id_company,
  id_ebdb_user,
  company_associations,
  hs_analytics_first_touch_converting_campaign,
  hs_analytics_last_touch_converting_campaign,
  hs_analytics_source,
  hs_analytics_source_data_1,
  hs_analytics_source_data_2,
  hs_latest_source_data_1,
  hs_latest_source_data_2,
  first_conversion_event_name,
  field_of_business,
  occupation,
  address,
  city,
  state,
  company,
  email,
  hs_email_domain,
  hs_whatsapp_phone_number,
  mobile_phone,
  phone,
  website,
  first_name,
  last_name,
  hs_marketable_status,
  life_cycle_stage,
  lead_origin_restricted_use,
  recent_conversion_event_name,
  nps_responsible,
  lead_status,
  lead_status_history,
  num_conversion_events,
  num_associated_deals,
  is_enrolled_in_sequence,
  has_been_in_demand_only_onboarding_live,
  is_archived,
  ts_first_conversion,
  ts_notes_last_updated,
  ts_notes_next_activity,
  ts_closed,
  ts_live_demand_only,
  ts_archived,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT
    CAST(c.id_contact AS BIGINT),
    CAST(GET_JSON_OBJECT(c.properties, '$.hubspot_owner_id') AS BIGINT) AS id_hubspot_owner,
    CAST(GET_JSON_OBJECT(c.associations, '$.companies.results[0].id') AS BIGINT) AS id_company,
    u.id AS id_ebdb_user,
    FROM_JSON(
      GET_JSON_OBJECT(c.associations, '$.companies.results'),
      'array<struct<id: string, type: string>>'
    ) AS company_associations,
    NULLIF(
      GET_JSON_OBJECT(c.properties, '$.hs_analytics_first_touch_converting_campaign'),
      ''
    ) AS hs_analytics_first_touch_converting_campaign,
    NULLIF(
      GET_JSON_OBJECT(c.properties, '$.hs_analytics_last_touch_converting_campaign'),
      ''
    ) AS hs_analytics_last_touch_converting_campaign,
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
      'array<struct<\n            value:string,\n            timestamp:timestamp,\n            sourceType:string,\n            sourceId:string,\n            sourceLabel:string,\n            updatedByUserId:string\n        >>'
    ) AS lead_status_history,
    CAST(GET_JSON_OBJECT(c.properties, '$.num_conversion_events') AS INT) AS num_conversion_events,
    CAST(GET_JSON_OBJECT(c.properties, '$.num_associated_deals') AS INT) AS num_associated_deals,
    CAST(GET_JSON_OBJECT(c.properties, '$.hs_sequences_is_enrolled') AS BOOLEAN) AS is_enrolled_in_sequence,
    CASE GET_JSON_OBJECT(c.properties, '$.demand_only__corretor_participou_da_live_de_onboarding_')
      WHEN 'Sim'
      THEN TRUE
      ELSE COALESCE(
        CAST(GET_JSON_OBJECT(c.properties, '$.demand_only__corretor_participou_da_live_de_onboarding_') AS BOOLEAN),
        FALSE
      )
    END AS has_been_in_demand_only_onboarding_live,
    c.is_archived,
    CAST(GET_JSON_OBJECT(c.properties, '$.first_conversion_date') AS TIMESTAMP) AS ts_first_conversion,
    CAST(GET_JSON_OBJECT(c.properties, '$.notes_last_updated') AS TIMESTAMP) AS ts_notes_last_updated,
    CAST(GET_JSON_OBJECT(c.properties, '$.notes_next_activity_date') AS TIMESTAMP) AS ts_notes_next_activity,
    CAST(GET_JSON_OBJECT(c.properties, '$.closedate') AS TIMESTAMP) AS ts_closed,
    CAST(GET_JSON_OBJECT(c.properties, '$.demand_only__data_da_live') AS TIMESTAMP) AS ts_live_demand_only,
    c.ts_archived,
    c.ts_created,
    c.ts_updated,
    c.year,
    c.month,
    c.day,
    ROW_NUMBER() OVER (PARTITION BY c.year, c.month, c.day, c.id_contact ORDER BY u.id_agent NULLS LAST /* Prioritize agents in an eventual clash of emails */) AS _w,
    u.id_agent
  FROM datalake_hubspot_clean.contact AS c
  LEFT JOIN datalake_ebdb_clean.`user` AS u
    ON TRIM(LOWER(NULLIF(GET_JSON_OBJECT(properties, '$.email'), ''))) = TRIM(LOWER(u.email))
  WHERE
    c.year = {year} AND c.month = {month} AND c.day = {day}
) AS _t
WHERE
  _w