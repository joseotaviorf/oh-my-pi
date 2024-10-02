SELECT
    id_company::BIGINT,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    GET_JSON_OBJECT(properties, '$.hubspot_team_id')::BIGINT AS id_hubspot_team,
    GET_JSON_OBJECT(properties, '$.hs_parent_company_id')::BIGINT AS id_parent_company,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_merged_object_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_merged_companies,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.atuacao_da_imobiliaria'), ''), ';') AS fields_of_business,
    NULLIF(GET_JSON_OBJECT(properties, '$.address'), '') AS address,
    NULLIF(GET_JSON_OBJECT(properties, '$.zip'), '') AS zip_code,
    NULLIF(GET_JSON_OBJECT(properties, '$.city'), '') AS city,
    COALESCE(
        NULLIF(GET_JSON_OBJECT(properties, '$.estado'), ''),
        NULLIF(GET_JSON_OBJECT(properties, '$.state'), '')
    ) AS state,
    NULLIF(GET_JSON_OBJECT(properties, '$.country'), '') AS country,
    NULLIF(GET_JSON_OBJECT(properties, '$.country_code'), '') AS country_code,
    NULLIF(GET_JSON_OBJECT(properties, '$.domain'), '') AS domain,
    NULLIF(GET_JSON_OBJECT(properties, '$.e_mail'), '') AS e_mail,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source'), '') AS hs_analytics_source,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source_data_1'), '') AS hs_analytics_source_data_1,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_source_data_2'), '') AS hs_analytics_source_data_2,
    NULLIF(GET_JSON_OBJECT(properties, '$.industry'), '') AS industry,
    NULLIF(GET_JSON_OBJECT(properties, '$.inside_sales'), '') AS inside_sales,
    NULLIF(GET_JSON_OBJECT(properties, '$.lifecyclestage'), '') AS life_cycle_stage,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_campain'), '') AS mkt_campain,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_channel'), '') AS mkt_channel,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_content'), '') AS mkt_content,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_medium'), '') AS mkt_medium,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_origin'), '') AS mkt_origin,
    NULLIF(GET_JSON_OBJECT(properties, '$.mkt_source'), '') AS mkt_source,
    NULLIF(GET_JSON_OBJECT(properties, '$.motivo_de_descarte'), '') AS discard_reason,
    NULLIF(GET_JSON_OBJECT(properties, '$.motivos_de_descarte_unificados'), '') AS unified_discard_reasons,
    NULLIF(GET_JSON_OBJECT(properties, '$.name'), '') AS name,
    NULLIF(GET_JSON_OBJECT(properties, '$.tag_imobiliarias'), '') AS tag_real_estate_agency,
    NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(properties, '$.tag_imobiliarias'), r'\[3(?i:p)(?i:BH)?\-(.+?)\]'), '') AS extracted_3p_tag,
    NULLIF(GET_JSON_OBJECT(properties, '$.esta_carteirizada_'), '') AS company_cluster,
    NULLIF(GET_JSON_OBJECT(properties, '$.tipo_de_membro'), '') AS member_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.categoria_do_membro'), '') AS member_category,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    NULLIF(GET_JSON_OBJECT(properties, '$.categoria_do_membro'), '') AS sale_member_category,
    NULLIF(GET_JSON_OBJECT(properties, '$.categoria_do_membro___for_rent'), '') AS rent_member_category,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.categoria_do_membro'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS member_category_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.categoria_do_membro'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS sale_member_category_history,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.categoria_do_membro___for_rent'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS rent_member_category_history,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.esta_carteirizada_'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS company_cluster_history,
    NULLIF(GET_JSON_OBJECT(properties, '$.origem_do_lead'), '') AS lead_origin,
    NULLIF(GET_JSON_OBJECT(properties, '$.phone'), '') AS phone,
    NULLIF(GET_JSON_OBJECT(properties, '$.tipo_de_parceria'), '') AS partnership_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.first_conversion_event_name'), '') AS first_conversion_event_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_analytics_first_touch_converting_campaign'), '') AS hs_analytics_first_touch_converting_campaign,
    NULLIF(GET_JSON_OBJECT(properties, '$.qual_'), '') AS crm,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.com_quais_imobiliarias_tem_parceria_'), ''), ';') AS partner_agencies,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.em_quais_portais_anuncia_'), ''), ';') AS advertising_portals,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.qual_a_solucao_empresa_de_garantia_locaticia_oferece_para_os_clientes_de_locacao_'), ''), ';') AS rental_guarantee_solutions,
    NULLIF(GET_JSON_OBJECT(properties, '$.qual_o_foco_da_imobiliaria_'), '') AS real_estate_agency_focus,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.trabalha_com_financiamento__se_sim__quais_bancos_'), ''), ';') AS financing_banks,
    CASE
        WHEN NULLIF(GET_JSON_OBJECT(properties, '$.country_code'), '') = 'BR'
        OR NULLIF(GET_JSON_OBJECT(properties, '$.country'), '') IN ('Brasil', 'Brazil')
        OR NULLIF(GET_JSON_OBJECT(properties, '$.country'), '') IS NULL THEN NULLIF(REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9]', ''), '')
    END AS cnpj,
    CASE
        WHEN NULLIF(GET_JSON_OBJECT(properties, '$.country_code'), '') = 'MX' THEN NULLIF(REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9A-Za-z]', ''), '')
    END AS rfc,
    NULLIF(REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9A-Za-z]', ''), '') as document,
    NULLIF(GET_JSON_OBJECT(properties, '$.creci'), '') AS creci,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.produto_de_interesse'), ''), ';') AS products_of_interest,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_lead_status'), '') AS lead_status,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_lead_status'), '') AS sale_lead_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.status_do_lead___for_rent'), '') AS rent_lead_status,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.hs_lead_status'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS lead_status_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.hs_lead_status'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS sale_lead_status_history,
    FROM_JSON(
        GET_JSON_OBJECT(properties_with_history, '$.status_do_lead___for_rent'),
        'array<struct<
            value:string,
            timestamp:timestamp,
            sourceType:string,
            sourceId:string,
            sourceLabel:string,
            updatedByUserId:string
        >>'
    ) AS rent_lead_status_history,
    NULLIF(GET_JSON_OBJECT(properties, '$.link_do_relatorio_consolidado'), '') AS report_link,
    NULLIF(GET_JSON_OBJECT(properties, '$.perfil_do_estoque'), '') AS inventory_profile,
    GET_JSON_OBJECT(properties, '$.cluster_performance') AS cluster_performance,
    GET_JSON_OBJECT(properties, '$.secretaria_o_responsavel') AS responsible_secretary,
    GET_JSON_OBJECT(properties, '$.expert_supply_responsavel') AS responsible_supply_expert,
    GET_JSON_OBJECT(properties, '$.expert_demand_responsavel') AS responsible_demand_expert,
    GET_JSON_OBJECT(properties, '$.pessoas_de_ops_supply_responsavel') AS responsible_operations_supply,
    GET_JSON_OBJECT(properties, '$.ccv_medio_mensal')::INT AS average_monthly_ccvs,
    GET_JSON_OBJECT(properties, '$.ccvs_mes_da_imobiliaria_sem_ser_com_rede_5a')::INT AS average_monthly_ccvs_outside_rede_quintoandar,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___quantidade_de_imoveis_a_venda')::INT AS num_properties_for_sale_farming_qualification,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___quantidade_de_imoveis_para_locacao')::INT AS num_properties_for_rent_farming_qualification,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___quantidade_de_corretores')::INT AS num_real_estate_agents_farming_qualification,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___quantidade_de_gerentes')::INT AS num_managers_farming_qualification,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___ticket_medio_de_imoveis_de_venda')::INT AS average_sale_property_ticket_farming_qualification,
    GET_JSON_OBJECT(properties, '$.qualificacao_farming___ticket_medio_de_imoveis_para_locacao')::INT AS average_rent_property_ticket_farming_qualification,
    COALESCE(GET_JSON_OBJECT(properties, '$.num_associated_deals')::INT, 0) AS num_associated_deals,
    COALESCE(GET_JSON_OBJECT(properties, '$.num_associated_contacts')::INT, 0) AS num_associated_contacts,
    GET_JSON_OBJECT(properties, '$.qual_a_media_de_novos_contratos_de_locacao_mes_')::INT AS monthly_average_new_rental_contracts,
    GET_JSON_OBJECT(properties, '$.quantidade_de_gerentes')::INT AS num_managers,
    GET_JSON_OBJECT(properties, '$.qual_a_quantidade_de_imoveis_administrados_')::INT AS num_managed_properties,
    GET_JSON_OBJECT(properties, '$.quantos_leads_recebem_por_mes')::INT AS num_monthly_leads,
    GET_JSON_OBJECT(properties, '$.ticket_medio_de_imoveis_de_venda')::INT AS average_sale_property_ticket,
    GET_JSON_OBJECT(properties, '$.ticket_medio_de_imoveis_para_locacao')::INT AS average_rent_property_ticket,
    GET_JSON_OBJECT(properties, '$.volume_de_repasse_mensal__vgv_r__')::INT AS monthly_repayment_volume_in_real,
    GET_JSON_OBJECT(properties, '$.volume_de_vendas__vgv_r__')::INT AS monthly_sale_volume_in_real,
    GET_JSON_OBJECT(properties, '$.quantidade_de_corretores')::INT AS num_real_estate_agents,
    GET_JSON_OBJECT(properties, '$.quantidade_de_imoveis_a_venda')::INT AS num_properties_for_sale,
    GET_JSON_OBJECT(properties, '$.quantidade_de_imoveis_para_locacao')::INT AS num_properties_for_rent,
    NULLIF(GET_JSON_OBJECT(properties, '$.utiliza_algum_crm_'), '') = 'Sim' AS has_crm,
    NULLIF(GET_JSON_OBJECT(properties, '$.anuncia_os_imoveis_online_'), '') = 'Sim' AS has_property_advertisement_online,
    NULLIF(GET_JSON_OBJECT(properties, '$.atua_como_correspondente_bancario_'), '') = 'Sim' AS is_correspondent_bank,
    NULLIF(GET_JSON_OBJECT(properties, '$.situacao_da_empresa'), '') = 'Sim' AS is_lost,
    NULLIF(GET_JSON_OBJECT(properties, '$.trabalha_com_financiamento_'), '') = 'Sim' AS has_financing,
    NULLIF(GET_JSON_OBJECT(properties, '$.trabalha_com_venda_e_locacao_'), '') LIKE '%Venda%' AS is_for_sale,
    NULLIF(GET_JSON_OBJECT(properties, '$.trabalha_com_venda_e_locacao_'), '') LIKE '%Locação%' AS is_for_rent,
    NULLIF(GET_JSON_OBJECT(properties, '$.esta_no_leadgen_'), '') = 'Sim' AS is_flagged_as_leadgen,
    NULLIF(GET_JSON_OBJECT(properties, '$.trabalha_em_parceria_com_outras_imobiliarias_'), '') = 'Sim' AS has_partnerships_with_other_agencies,
    NULLIF(GET_JSON_OBJECT(properties, '$.digito_creci'), '') = 'PF' AS is_natural_person,
    NULLIF(GET_JSON_OBJECT(properties, '$.digito_creci'), '') = 'PJ' AS is_juridical_person,
    is_archived,
    GET_JSON_OBJECT(properties, '$.first_conversion_date')::TIMESTAMP AS ts_first_conversion,
    GET_JSON_OBJECT(properties, '$.recent_deal_close_date')::TIMESTAMP AS ts_recent_deal_close,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_assigneddate')::TIMESTAMP AS ts_hubspot_owner_assigned,
    GET_JSON_OBJECT(properties, '$.hs_last_logged_call_date')::TIMESTAMP AS ts_last_logged_call,
    GET_JSON_OBJECT(properties, '$.notes_last_updated')::TIMESTAMP AS ts_notes_last_updated,
    GET_JSON_OBJECT(properties, '$.demand_only__data_da_live')::TIMESTAMP AS ts_live_demand_only,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.company
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}