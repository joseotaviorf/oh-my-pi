WITH business_unit_by_hub_id AS (
  SELECT
    bu.id AS id_hub,
    bu.hub_name,
    bu.business_context
  FROM
    datalake_hub_services_clean.business_unit AS bu
  WHERE 
    bu.business_context = 'SALE'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY bu.id ORDER BY bu.ts_updated DESC) = 1
),
base_visits AS (      
  SELECT 
    b.id_visit AS id,  
    b.id_house,
    b.id_visitor,
    b.id_agent,
    --TODO: TROCAR PELO CAMPO DA TABELA DE ORIGEM (id_user_sale_attendence_5a)    
    CASE
      WHEN b.id_agent <> b.id_user_visit_request THEN b.id_user_visit_request
      ELSE NULL
    END AS id_user_secretariat_booking_creator,
    --FIM TODO: TROCAR PELO CAMPO DA TABELA DE ORIGEM
    b.id_company_supply,
    b.id_company_demand,
    b.partner_3p_demand AS partner_3p_demand,    
    b.visit_request_channel AS visit_channel, 
    b.is_3p_supply,
    b.is_3p_demand,
    b.is_3p_lead_gen,
    b.has_3p_access_control,
    b.is_canceled,  
    b.ts_visit,
    b.ts_created AS ts_booking_created             
  FROM    
    datalake_visit.visits AS b
  WHERE
      b.business_context = 'SALE'
  AND b.is_completed = TRUE
),
visit_offer AS (    
  SELECT
    eso.id_offer,
    eso.id_buyer,
    bs.id AS id_booking,
    bs.id_agent,
    bs.id_user_secretariat_booking_creator,
    bs.id_company_supply,
    bs.id_company_demand,
    bs.partner_3p_demand,
    bs.is_3p_supply,
    bs.is_3p_demand,
    bs.is_3p_lead_gen,
    bs.has_3p_access_control,
    CASE
      WHEN bs.ts_booking_created < eso.ts_offer_created THEN TRUE
      ELSE FALSE
    END AS flg_booking_before_offer,
    CASE
      WHEN bs.ts_visit < eso.ts_offer_created THEN TRUE
      ELSE FALSE
    END AS flg_visit_completed_before_offer,
    (unix_timestamp(eso.ts_offer_created)-unix_timestamp(bs.ts_booking_created))/(3600) AS hours_booking_to_offer,
    (unix_timestamp(eso.ts_offer_created)-unix_timestamp(bs.ts_visit))/(3600) AS hours_visit_to_offer,    
    bs.ts_booking_created ,
    bs.ts_visit,
    bs.visit_channel,
    eso.ts_offer_created
  FROM
    datalake_sale_offer.core_sale_offer AS eso
  JOIN
    base_visits AS bs
        ON bs.id_house = eso.id_house
        AND bs.id_visitor = eso.id_buyer
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY
          eso.id_offer
      ORDER BY
          bs.ts_visit
    ) = 1
),
rank_offers AS (
  SELECT
    o.id_offer AS id,
    ROW_NUMBER() OVER (
        PARTITION BY
            o.id_buyer
                ORDER BY o.ts_offer_created
    ) AS buyer_rank_offers,
    ROW_NUMBER() OVER (
        PARTITION BY
            o.id_house
                ORDER BY o.ts_offer_created
    ) AS house_rank_offers
  FROM
        datalake_sale_offer.core_sale_offer as o
),
sales_flow_details AS (
  SELECT
    sfd.id,
    sfd.id_sales_flow,        
    sfd.ts_seller_fup,
    sfd.ts_buyer_fup,
    sfd.ts_updated
  FROM
    datalake_sales_flow_clean.sales_flow_details AS sfd
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY 
        sfd.id_sales_flow
      ORDER BY
        sfd.ts_updated DESC
    ) = 1
)

SELECT    
    o.id_offer,
    o.id_sales_flow,
    o.id_sale_flow,
    o.id_buyer,
    o.id_house,
    o.id_owner,
    o.id_region,
    r.city_group,
    o.id_agent,    
    vo.id_booking,
    o.id_hub AS id_business_unit,
    vo.id_company_supply,
    vo.id_company_demand,
    vo.is_3p_supply,
    vo.is_3p_demand,
    vo.is_3p_lead_gen,
    vo.has_3p_access_control,
    vo.id_user_secretariat_booking_creator,
    o.flow_type,
    CASE
      WHEN o.flow_type = 'DEAL_MAKING'
        THEN 'DEAL_MAKING' -- Offers que não estão na planilha de trabalho e o Vendas diz ser DM
      ELSE COALESCE(o.flow_type,'NOT DEFINED') -- Offers que não estão na planilha de trabalho, não foram atribuidas a um deal maker e possuem offer_flows diferentes de DM no Vendas.
    END AS offer_flow,
    o.current_payment_method,
    o.planned_payment_method,
    o.credit_model,
    o.has_used_fgts_in_payment,
    o.brokerage_fee,
    o.sale_price,
    o.first_price_offered_by_buyer,
    o.last_price_offered_by_buyer,
    o.sale_price_agreed,
    o.first_discount_proposed,
    o.last_discount_proposed,
    o.payment_entry_amount,
    o.registry_price,
    o.itbi_price,
    o.has_used_negotiation_chat,
    o.status AS offer_status,
    o.drop_reason,
    o.drop_reason_responsible,    
    bu.hub_name AS business_unit,
    o.is_a_rescued_offer,
    slpc.price_segment,    
    bpt.id_buyer_prospect_type,    
    sp.id_user_agent,
    sp.id_user_team_lead,
    sp.id_user_consultant,
    sp.id_consultant,
    sp.id_user_consultant AS id_closing_specialist,
    vo.flg_booking_before_offer,
    vo.flg_visit_completed_before_offer,
    CASE
      WHEN rk.buyer_rank_offers = 1
        THEN TRUE
      ELSE FALSE
    END AS is_buyer_first_offer,
    CASE
      WHEN rk.house_rank_offers = 1
        THEN TRUE
      ELSE FALSE
    END AS is_house_first_offer,
    vo.ts_booking_created,
    vo.hours_booking_to_offer,
    vo.hours_visit_to_offer,
    CASE
        WHEN DATE(o.ts_offer_created) <= DATE(o.ts_offer_accepted)
        THEN DATEDIFF(DATE(o.ts_offer_accepted), DATE(o.ts_offer_created))
    END AS days_offer_submitted_to_offer_accepted,

    CASE
        WHEN DATE(o.ts_offer_created) <= DATE(o.ts_sale_agreement_created)
        THEN DATEDIFF(DATE(o.ts_sale_agreement_created), DATE(o.ts_offer_created))
    END AS days_offer_submitted_to_sale_agreement_created,
    
    CASE
        WHEN DATE(o.ts_offer_created) <= DATE(o.ts_offer_discarded)
        THEN DATEDIFF(DATE(o.ts_offer_discarded), DATE(o.ts_offer_created))
    END AS days_offer_submitted_to_offer_dismissed,

    CASE
        WHEN DATE(o.ts_offer_created) <= DATE(o.ts_sale_agreement_signed)
        THEN DATEDIFF(DATE(o.ts_sale_agreement_signed), DATE(o.ts_offer_created))
    END AS days_offer_submitted_to_sale_agreement_signed,

    CASE
        WHEN DATE(o.ts_offer_accepted) <= DATE(o.ts_sale_agreement_created)
        THEN DATEDIFF(DATE(o.ts_sale_agreement_created), DATE(o.ts_offer_created))
    END AS days_offer_accepted_to_sale_agreement_created,

    CASE
        WHEN DATE(o.ts_offer_accepted) <= DATE(o.ts_sale_agreement_signed)
        THEN DATEDIFF(DATE(o.ts_sale_agreement_signed), DATE(o.ts_offer_created))
    END AS days_offer_accepted_to_sale_agreement_signed,

    CASE
        WHEN DATE(o.ts_offer_accepted) <= DATE(o.ts_offer_discarded)
        THEN DATEDIFF(DATE(o.ts_offer_discarded), DATE(o.ts_offer_created))
    END AS days_offer_accepted_to_offer_dismissed,
    
    CASE
        WHEN DATE(o.ts_sale_agreement_created) <= DATE(o.ts_sale_agreement_signed)
        THEN DATEDIFF(DATE(o.ts_sale_agreement_signed), DATE(o.ts_sale_agreement_created))
    END AS days_sale_agreement_created_to_sale_agreement_signed,
    o.ts_offer_created AS ts_offer_submitted,
    o.ts_offer_accepted,
    o.ts_offer_discarded AS ts_offer_dismissed,
    o.ts_offer_canceled,
    o.ts_offer_rescued,
    o.ts_sale_agreement_created,
    o.ts_sale_agreement_signed,
    sfd.ts_seller_fup,
    sfd.ts_buyer_fup,
    o.ts_updated, 
    now() as ts_load
FROM
  datalake_sale_offer.core_sale_offer AS o
  --core_sales_offer AS o
LEFT JOIN
  visit_offer AS vo
  ON o.id_offer = vo.id_offer
LEFT JOIN
  datalake_hub_services_clean.business_unit AS bu
  ON o.id_hub = bu.id
LEFT JOIN
  rank_offers AS rk
  ON rk.id = o.id_offer
LEFT JOIN
  sales_flow_details AS sfd
  ON sfd.id_sales_flow = o.id_sales_flow
LEFT JOIN datalake_region.region AS r
  ON o.id_region = r.id
LEFT JOIN
  datalake_sale_listings.sale_listing_price_changes AS slpc
  ON o.id_house = slpc.id_house
  AND o.ts_offer_created >= slpc.ts_price_started 
  AND o.ts_offer_created < COALESCE(slpc.ts_price_ended, NOW())
LEFT JOIN
  datalake_buyer_prospect.buyer_prospect_type AS bpt
  ON o.id_buyer = bpt.id_prospect
  AND r.city_group = bpt.city_group
  AND o.ts_offer_created >= bpt.ts_activation 
  AND o.ts_offer_created < COALESCE(bpt.ts_activation_end, NOW())
LEFT JOIN
  datalake_sale_offer_flows.offer_specialists AS sp
  ON o.id_offer = sp.id_offer