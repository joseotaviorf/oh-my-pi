WITH sale_visit_flows AS (
  SELECT 
    b.id_visit,
    b.id_house,
    b.id_visitor AS id_buyer,
    b.id_agent,
    b.id_user_sale_agent,
    b.id_sale_flow,
    FIRST_VALUE(b.user_sale_booking_creator) OVER(PARTITION BY b.id_visit ORDER BY b.ts_created_local_tz) AS first_visit_creation_origin,
    b.user_sale_booking_creator AS visit_creation_origin,
    b.last_update_source AS visit_update_origin,
    b.code AS visit_code,
    CASE 
      WHEN status = 'Realizado' AND b.visit_fup in ('EntradaNaoAutorizada','NaoCompareceu')
        THEN 'Cancelado'
      ELSE b.status
    END AS visit_status,
    b.ts_booking_utc AS ts_visit_scheduled_for,
    FIRST_VALUE(b.ts_created_local_tz) OVER(PARTITION BY b.id_visit ORDER BY b.ts_created_local_tz) AS ts_first_visit_created,
    b.ts_created_local_tz AS ts_visit_created,
    b.ts_updated AS ts_visit_updated
  FROM 
    datalake_booking.booking AS b
  WHERE
    b.type = 'Visita'
    AND b.visit_intent = 'SALE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY b.id_visit ORDER BY b.ts_updated DESC) = 1
)
  SELECT
    svf.id_visit,
    svf.id_house,
    svf.id_buyer,
    svf.id_agent,
    COALESCE(svf.id_sale_flow, so.id_sale_flow) AS id_sales_flow,
    tqc.id_referral_flow,
    so.id_offer,
    svf.first_visit_creation_origin,
    svf.visit_creation_origin,
    svf.visit_update_origin,
    svf.visit_code,
    svf.visit_status,
    tqc.tqc_flow,
    CASE 
      WHEN tqc.tqc_flow = 'Old'
        THEN 1
      WHEN tqc.tqc_flow = 'New'
        THEN 2
      ELSE NULL 
    END AS id_tqc_flow,
    CASE 
      WHEN tqc.id_user_lead IS NOT NULL
        THEN TRUE
      ELSE FALSE
    END AS is_tqc,
    tqc.ts_created AS ts_tqc_referral,  
    svf.ts_visit_scheduled_for,
    svf.ts_first_visit_created,
    svf.ts_visit_created,
    svf.ts_visit_updated,
    so.ts_offer_submitted,
    so.dt_offer_accepted AS ts_offer_accepted,
    so.dt_sale_agreement_created AS ts_sale_agreement_created,
    so.dt_sale_agreement_signed AS ts_sale_agreement_signed
  FROM 
    sale_visit_flows AS svf
  FULL OUTER JOIN
    datalake_offer.sale_offer AS so
      ON svf.id_sale_flow = so.id_sale_flow
  LEFT JOIN 
    datalake_tqc_referral.unified_lead_referral_flow AS tqc
      ON CONCAT(COALESCE(svf.id_agent,svf.id_user_sale_agent,so.id_agent,so.id_user_agent),'_',COALESCE(svf.id_buyer, so.id_buyer)) = tqc.id_referral_flow
    AND (tqc.status = 'TRUE' OR tqc.status = 'CONFIRMED')
    AND DATE(COALESCE(svf.ts_first_visit_created, so.ts_offer_submitted)) >= DATE(DATE_ADD(tqc.ts_created,-7))
  WHERE
    tqc.id_referral_flow IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY COALESCE(svf.id_visit,so.id_offer), id_referral_flow ORDER BY id_tqc_flow DESC, svf.ts_visit_created, so.ts_offer_submitted) = 1