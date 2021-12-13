SELECT
  ohc.id_offer,
  ohc.id_client_cm,
  ohc.id_user_5a AS id_buyer,
  ohc.id_house_cm,
  ohc.id_house_5a AS id_house,
  ohc.status,
  ohc.offer_model,
  ohc.executive,
  ohc.executive_lead,
  ohc.sale_price_agreed,
  ohc.agent,
  CASE
    WHEN ohc.offer_flow LIKE '%HUB%' 
      THEN 'HUB'
    WHEN ohc.offer_flow LIKE '%CENTRAL%' 
      THEN 'CENTRAL'
  END AS ohc_offer_flow,
  CASE
    WHEN ohc.executive_lead = 'Leonardo Monteiro'
      OR ohc.offer_flow = 'HUB_BV_V0' 
        THEN 'HUB Bela Vista'
    WHEN ohc.executive_lead LIKE '%Muller%'
        OR ohc.executive_lead LIKE '%Muller%' 
          THEN 'HUB Vila Madalena'
    WHEN LOWER(ohc.executive_lead) LIKE '%karina%' 
      THEN 'HUB Perdizes'
    WHEN ohc.executive_lead = 'Rodrigo Pereira'
      OR ohc.offer_flow = 'HUB_VM_V0' 
        THEN 'HUB Vila Mariana'
    ELSE ohc.offer_flow
  END AS ohc_offer_flow_detail,
  
  ohc.dt_offer_submitted,
  ohc.dt_offer_ended,
  ohc.dt_offer_accepted,
  ohc.dt_offer_dismissed,
  ohc.dt_sale_agreement_signed
FROM
  datalake_gsheets_clean.offers_hub_central ohc