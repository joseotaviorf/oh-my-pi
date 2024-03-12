SELECT
    id_ticket::BIGINT,
    GET_JSON_OBJECT(associations, '$.deals.results[0].id')::BIGINT AS id_deal,
    FILTER( -- There can be more than one company, but we only want the main one (type = "ticket_to_company")
        FROM_JSON(
            GET_JSON_OBJECT(associations, '$.companies.results'),
            'array<struct<id: string, type: string>>'
        ),
        x -> x["type"] = "ticket_to_company"
    )[0]["id"]::BIGINT AS id_company,
    GET_JSON_OBJECT(properties, '$.hs_pipeline_stage')::BIGINT AS id_stage,
    GET_JSON_OBJECT(properties, '$.hs_pipeline')::BIGINT AS id_pipeline,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    FROM_JSON(
        NULLIF(GET_JSON_OBJECT(properties_with_history, '$.hs_pipeline_stage'), '[]'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS id_stage_history,
    FROM_JSON(
        NULLIF(GET_JSON_OBJECT(properties_with_history, '$.hs_pipeline'), '[]'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS id_pipeline_history,
    NULLIF(GET_JSON_OBJECT(properties, '$.content'), '') AS content,
    NULLIF(GET_JSON_OBJECT(properties, '$.subject'), '') AS subject,
    NULLIF(GET_JSON_OBJECT(properties, '$.tipo_de_onboarding'), '') AS onboarding_type,
    GET_JSON_OBJECT(properties, '$.field_sales')::BIGINT AS field_sales,
    GET_JSON_OBJECT(properties, '$.aceita_contato_comunicacao_com_os_corretores_')::BOOLEAN AS has_accepted_contact_with_agents,
    is_archived,
    GET_JSON_OBJECT(properties, '$.data_de_assinatura_do_termo')::TIMESTAMP AS dt_term_signed,
    GET_JSON_OBJECT(properties, '$.data_de_envio_do_termo')::TIMESTAMP AS dt_term_sent,
    GET_JSON_OBJECT(properties, '$.data_de_recebimento_dos_documentos')::TIMESTAMP AS dt_documents_received,
    GET_JSON_OBJECT(properties, '$.data_do_onboarding_realizado')::TIMESTAMP AS dt_onboarding,
    GET_JSON_OBJECT(properties, '$.demand_only__data_da_live')::TIMESTAMP AS ts_live_demand_only,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.ticket
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}