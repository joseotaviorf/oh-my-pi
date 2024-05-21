WITH 
plaquinhas_users AS (
    SELECT
        id_user,
        final_attribution_origin, -- Secretaria / CX / App / Web
        CASE WHEN final_attribution_origin in ('App', 'Web') THEN 'QR Code' ELSE final_attribution_medium END AS final_attribution_medium, -- Canal: Chat, Telefone, QR Code, E-mail, WhatsApp, Presencial, Null
        min(ts_event::DATE) AS dt_first_interaction,
        max(ts_event::DATE) AS dt_last_interaction
    FROM
        datalake_tracked_events.cross_channel_full
    WHERE
        id_user > 0
        AND (final_attribution_source IN ('Placas', 'Quinto Andar - Placas') 
        OR final_attribution_source LIKE '%plaquinha%')
    GROUP BY 1, 2, 3
),
metrics_base AS (
    SELECT
          u.id_user,
          u.dt_first_interaction,
          u.dt_last_interaction,
          u.final_attribution_origin,
          u.final_attribution_medium,
          'Rent'::STRING AS business_context,
          rent.sk_booking,
          rent.sk_offer,
          rent.sk_proposal,
          rent.sk_contract,
          rent.sk_rf AS sk_flow, -- renamed column to fit rent_flows and sale_flows
          rent.city_group,
          rent.flow_event,
          rent.mkt_origin,
          rent.mkt_channel,
          rent.mkt_medium,
          rent.mkt_source,
          rent.utm_campaign,
          rent.utm_term,
          rent.utm_content,
          rent.campaign_name,
          rent.status,
          rent.rent_flow_order AS flow_order, -- renamed column to fit rent_flows and sale_flows
          rent.tenant_prospect_order,
          rent.dt_event,
          rent.dt_booking_created,
          rent.flg_visit_completed,
          rent.dt_offer_submitted,
          rent.dt_offer_approved,
          rent.dt_tenant_first_doc_sent,
          rent.dt_credit_analysis_approved,
          rent.dt_contract_signed,
          NULL::BOOLEAN AS is_3p,
          NULL::DOUBLE AS visits_booked_target,
          NULL:DOUBLE AS marketing_cost
        FROM
          plaquinhas_users u
        LEFT JOIN dw_datamarts.performance_marketing_metrics_demand AS rent
            ON u.id_user = rent.sk_client AND rent.dt_event BETWEEN u.dt_first_interaction AND dateadd(day, 90, u.dt_last_interaction)
        UNION ALL
        SELECT
          u.id_user,
          u.dt_first_interaction,
          u.dt_last_interaction,
          u.final_attribution_origin,
          u.final_attribution_medium,
          'Sale'::STRING AS business_context,
          sale.sk_booking,
          sale.sk_offer,
          NULL::STRING AS sk_proposal,
          NULL::STRING AS sk_contract,
          sale.sk_sale_flow AS sk_flow, -- renamed column to fit rent_flows and sale_flows
          sale.city_group,
          sale.flow_event,
          sale.mkt_origin,
          sale.mkt_channel,
          sale.mkt_medium,
          sale.mkt_source,
          sale.utm_campaign,
          sale.utm_term,
          sale.utm_content,
          sale.campaign_name,
          sale.status,
          sale.sale_flow_order AS flow_order, -- renamed column to fit rent_flows and sale_flows
          sale.buyer_prospect_order AS prospects_order, -- renamed column to fit rent_prospects_order and buyer_prospects_order
          sale.dt_event,
          sale.dt_booking_created,
          CASE WHEN sale.dt_visit_completed IS NOT NULL THEN TRUE ELSE FALSE END AS flg_visit_completed,
          sale.dt_offer_submitted,
          sale.dt_offer_accepted AS dt_offer_approved, -- renamed column to fit dt_offer_approved and  dt_offer_accepted for rent and sale
          NULL::DATE AS dt_tenant_first_doc_sent,
          NULL::DATE AS dt_credit_analysis_approved,
          sale.dt_sale_agreement_signed AS dt_contract_signed, -- renamed column to fit dt_contract_signed and dt_sale_agreement_signed for rent and sale
          sale.is_3p::BOOLEAN AS is_3p,        
          NULL::DOUBLE AS visits_booked_target,
          NULL:DOUBLE AS marketing_cost
        FROM
          plaquinhas_users u
        LEFT JOIN dw_datamarts.sale_performance_marketing_metrics_demand sale
            ON u.id_user = sale.sk_buyer AND sale.dt_event BETWEEN u.dt_first_interaction AND dateadd(day, 90, u.dt_last_interaction)
),
marketing_cost AS (
        SELECT
            NULL::STRING AS id_user,
            dt_event AS dt_first_interaction,
            dt_event AS dt_last_interaction,
            NULL::STRING AS final_attribution_origin,
            NULL::STRING AS final_attribution_medium,
            'Rent'::STRING AS business_context,
            NULL::BIGINT AS sk_booking,
            NULL::BIGINT AS sk_offer,
            NULL::BIGINT AS sk_proposal,
            NULL::BIGINT AS sk_contract,
            NULL::BIGINT AS sk_flow, 
            NULL::STRING AS city_group,
            NULL::STRING AS flow_event,
            NULL::STRING AS mkt_origin,
            NULL::STRING AS mkt_channel,
            NULL::STRING AS mkt_medium,
            NULL::STRING AS mkt_source,
            NULL::STRING AS utm_campaign,
            NULL::STRING AS utm_term,
            NULL::STRING AS utm_content,
            NULL::STRING AS campaign_name,
            NULL::STRING AS status,
            NULL::BIGINT AS flow_order, 
            NULL::BIGINT AS prospects_order, 
            NULL::DATE AS dt_event,
            NULL::DATE AS dt_booking_created,
            NULL::BOOLEAN AS  flg_visit_completed,
            NULL::DATE AS dt_offer_submitted,
            NULL::DATE AS dt_offer_approved, 
            NULL::DATE AS dt_tenant_first_doc_sent,
            NULL::DATE AS dt_credit_analysis_approved,
            NULL::DATE AS dt_contract_signed, 
            NULL::BOOLEAN AS is_3p,        
            NULL::DOUBLE AS visits_booked_target,
            marketing_cost
      FROM dw_datamarts.performance_marketing_metrics_demand
      WHERE
          mkt_medium = 'Placas'  
      UNION ALL         
      SELECT
            NULL::STRING AS id_user,
            dt_event AS dt_first_interaction,
            dt_event AS dt_last_interaction,
            NULL::STRING AS final_attribution_origin,
            NULL::STRING AS final_attribution_medium,
            'Sale'::STRING AS business_context,
            NULL::BIGINT AS sk_booking,
            NULL::BIGINT AS sk_offer,
            NULL::BIGINT AS sk_proposal,
            NULL::BIGINT AS sk_contract,
            NULL::BIGINT AS sk_flow, 
            NULL::STRING AS city_group,
            NULL::STRING AS flow_event,
            NULL::STRING AS mkt_origin,
            NULL::STRING AS mkt_channel,
            NULL::STRING AS mkt_medium,
            NULL::STRING AS mkt_source,
            NULL::STRING AS utm_campaign,
            NULL::STRING AS utm_term,
            NULL::STRING AS utm_content,
            NULL::STRING AS campaign_name,
            NULL::STRING AS status,
            NULL::BIGINT AS flow_order, 
            NULL::BIGINT AS prospects_order, 
            NULL::DATE AS dt_event,
            NULL::DATE AS dt_booking_created,
            NULL::BOOLEAN AS  flg_visit_completed,
            NULL::DATE AS dt_offer_submitted,
            NULL::DATE AS dt_offer_approved,
            NULL::DATE AS dt_tenant_first_doc_sent,
            NULL::DATE AS dt_credit_analysis_approved,
            NULL::DATE AS dt_contract_signed, 
            NULL::BOOLEAN AS is_3p,        
            NULL::DOUBLE AS visits_booked_target,
            marketing_cost
      FROM dw_datamarts.sale_performance_marketing_metrics_demand
      WHERE
          mkt_medium = 'Placas'
),
targets AS (
      SELECT
            NULL::STRING AS id_user,
            NULL::DATE AS dt_first_interaction,
            NULL::DATE AS dt_last_interaction,
            NULL::STRING AS final_attribution_origin,
            tgt.channel AS final_attribution_medium,
            tgt.business_context AS business_context,
            NULL::BIGINT AS sk_booking,
            NULL::BIGINT AS sk_offer,
            NULL::BIGINT AS sk_proposal,
            NULL::BIGINT AS sk_contract,
            NULL::BIGINT AS sk_flow,
            tgt.city_group AS city_group,
            NULL::STRING AS flow_event,
            NULL::STRING AS mkt_origin,
            NULL::STRING AS mkt_channel,
            NULL::STRING AS mkt_medium,
            NULL::STRING AS mkt_source,
            NULL::STRING AS utm_campaign,
            NULL::STRING AS utm_term,
            NULL::STRING AS utm_content,
            NULL::STRING AS campaign_name,
            NULL::STRING AS status,
            NULL::BIGINT AS flow_order, 
            NULL::BIGINT AS prospects_order, 
            NULL::DATE AS dt_event,
            tgt.dt_target AS dt_booking_created,
            NULL::BOOLEAN AS  flg_visit_completed,
            NULL::DATE AS dt_offer_submitted,
            NULL::DATE AS dt_offer_approved, 
            NULL::DATE AS dt_tenant_first_doc_sent,
            NULL::DATE AS dt_credit_analysis_approved,
            NULL::DATE AS dt_contract_signed, 
            NULL::BOOLEAN AS is_3p,        
            tgt.visits_booked_target AS visits_booked_target,
            NULL::DOUBLE AS marketing_cost
        FROM
          datalake_gsheets_clean.plaquinhas_demand_targets AS tgt
)
-------------------------------
-- UNION results and targets --
-------------------------------
SELECT
    mb.*
FROM
    metrics_base mb
UNION ALL
SELECT
    mc.*
FROM
    marketing_cost mc
UNION ALL
SELECT
    t.*
FROM
    targets t