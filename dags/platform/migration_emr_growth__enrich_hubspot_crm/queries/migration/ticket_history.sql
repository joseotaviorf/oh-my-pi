SELECT
  CAST(id_ticket AS BIGINT),
  CAST(GET_JSON_OBJECT(associations, '$.deals.results[0].id') AS BIGINT) AS id_deal,
  CAST(FILTER(
    FROM_JSON(
      GET_JSON_OBJECT(associations, '$.companies.results'),
      'array<struct<id: string, type: string>>'
    ),
    x -> x['type'] = 'ticket_to_company'
  )[0]['id'] AS BIGINT) AS id_company,
  CAST(GET_JSON_OBJECT(properties, '$.hs_pipeline_stage') AS BIGINT) AS id_stage,
  CAST(GET_JSON_OBJECT(properties, '$.hs_pipeline') AS BIGINT) AS id_pipeline,
  CAST(GET_JSON_OBJECT(properties, '$.hubspot_owner_id') AS BIGINT) AS id_hubspot_owner,
  FROM_JSON(
    NULLIF(GET_JSON_OBJECT(properties_with_history, '$.hs_pipeline_stage'), '[]'),
    'array<struct<\n            value:string,\n            timestamp:timestamp,\n            sourceType:string,\n            sourceId:string,\n            sourceLabel:string,\n            updatedByUserId:string\n        >>'
  ) AS id_stage_history,
  FROM_JSON(
    NULLIF(GET_JSON_OBJECT(properties_with_history, '$.hs_pipeline'), '[]'),
    'array<struct<\n            value:string,\n            timestamp:timestamp,\n            sourceType:string,\n            sourceId:string,\n            sourceLabel:string,\n            updatedByUserId:string\n        >>'
  ) AS id_pipeline_history,
  NULLIF(GET_JSON_OBJECT(properties, '$.content'), '') AS content,
  NULLIF(GET_JSON_OBJECT(properties, '$.subject'), '') AS subject,
  NULLIF(GET_JSON_OBJECT(properties, '$.tipo_de_onboarding'), '') AS onboarding_type,
  CAST(GET_JSON_OBJECT(properties, '$.field_sales') AS BIGINT) AS field_sales,
  CAST(GET_JSON_OBJECT(properties, '$.aceita_contato_comunicacao_com_os_corretores_') AS BOOLEAN) AS has_accepted_contact_with_agents,
  is_archived,
  CAST(GET_JSON_OBJECT(properties, '$.data_de_assinatura_do_termo') AS TIMESTAMP) AS dt_term_signed,
  CAST(GET_JSON_OBJECT(properties, '$.data_de_envio_do_termo') AS TIMESTAMP) AS dt_term_sent,
  CAST(GET_JSON_OBJECT(properties, '$.data_de_recebimento_dos_documentos') AS TIMESTAMP) AS dt_documents_received,
  CAST(GET_JSON_OBJECT(properties, '$.data_do_onboarding_realizado') AS TIMESTAMP) AS dt_onboarding,
  CAST(GET_JSON_OBJECT(properties, '$.demand_only__data_da_live') AS TIMESTAMP) AS ts_live_demand_only,
  ts_archived,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM datalake_hubspot_clean.ticket
WHERE
  year = {year} AND month = {month} AND day = {day}