WITH business_unit_by_hub_id AS (
  SELECT
    id_hub,
    hub_name,
    business_context
  FROM (
    SELECT
      bu.id AS id_hub,
      bu.hub_name,
      bu.business_context,
      ROW_NUMBER() OVER (PARTITION BY bu.id ORDER BY bu.ts_updated DESC) AS _w,
      bu.id,
      bu.ts_updated
    FROM datalake_hub_services_clean.business_unit AS bu
    WHERE
      bu.business_context = 'SALE'
  ) AS _t
  WHERE
    _w = 1
), base_visits AS (
  SELECT
    b.id_schedule AS id_booking,
    b.id_visit,
    b.id_house,
    b.id_visitor,
    b.id_agent,
    CASE
      WHEN v.id_agent <> v.id_user_visit_request
      THEN v.id_user_visit_request
      ELSE NULL
    END AS id_user_secretariat_booking_creator, /* TODO: TROCAR PELO CAMPO DA TABELA DE ORIGEM (id_user_sale_attendence_5a)    */
    b.id_company_supply, /* FIM TODO: TROCAR PELO CAMPO DA TABELA DE ORIGEM */
    b.id_company_demand,
    COALESCE(b.sk_broker_supply, v.sk_broker_supply) AS sk_broker_supply,
    COALESCE(b.sk_broker_demand, v.sk_broker_demand) AS sk_broker_demand,
    v.partner_3p_demand AS partner_3p_demand,
    v.visit_request_channel AS visit_channel,
    b.id_succeed_schedule,
    b.is_3p_supply,
    b.is_3p_demand,
    b.is_3p_lead_gen,
    b.has_3p_access_control,
    b.is_canceled,
    b.ts_visit,
    b.ts_schedule_created AS ts_booking_created
  FROM datalake_visit.visit_schedules AS b
  LEFT JOIN datalake_visit.visits AS v
    ON b.id_visit = v.id_visit
  WHERE
    b.business_context = 'SALE'
), salesflow_visit AS (
  SELECT
    sf.id AS id_sales_flow,
    sf.id_visit_external AS id_visit,
    vs.id_booking
  FROM datalake_sales_flow_clean.sales_flow AS sf
  LEFT JOIN base_visits AS vs
    ON vs.id_visit = sf.id_visit_external
  WHERE
    vs.id_succeed_schedule IS NULL /* PEGA O AGENDAMENTO ATIVO DA VISITA */
    AND sf.ts_created < CURRENT_DATE()
), last_visit AS (
  SELECT
    id_sales_flow,
    id_visit,
    id_booking
  FROM (
    SELECT
      eso.id_sales_flow,
      bs.id_visit,
      bs.id_booking,
      ROW_NUMBER() OVER (PARTITION BY eso.id_offer ORDER BY bs.ts_visit DESC) AS _w,
      eso.id_offer,
      bs.ts_visit
    FROM datalake_sale_offer.core_sale_offer AS eso
    LEFT JOIN base_visits AS bs
      ON bs.id_house = eso.id_house AND bs.id_visitor = eso.id_buyer
  ) AS _t
  WHERE
    _w = 1
), union_visits AS (
  SELECT
    sfv.id_sales_flow,
    sfv.id_visit,
    sfv.id_booking,
    '1 - Sales Flow' AS visit_link_type
  FROM salesflow_visit AS sfv
  UNION ALL
  SELECT
    lv.id_sales_flow,
    lv.id_visit,
    lv.id_booking,
    '2 - Last Visit' AS visit_link_type
  FROM last_visit AS lv
), visit_offer AS (
  SELECT
    id_offer,
    id_visit,
    id_buyer,
    id_sales_flow,
    id_booking,
    id_agent,
    id_user_secretariat_booking_creator,
    id_company_supply,
    id_company_demand,
    sk_broker_supply,
    sk_broker_demand,
    partner_3p_demand,
    is_3p_supply,
    is_3p_demand,
    is_3p_lead_gen,
    visit_link_type,
    has_3p_access_control,
    flg_booking_before_offer,
    flg_visit_completed_before_offer,
    hours_booking_to_offer,
    hours_visit_to_offer,
    ts_booking_created,
    ts_visit,
    visit_channel,
    ts_offer_created
  FROM (
    SELECT
      eso.id_offer,
      bs.id_visit,
      eso.id_buyer,
      eso.id_sales_flow,
      bs.id_booking,
      bs.id_agent,
      bs.id_user_secretariat_booking_creator,
      bs.id_company_supply,
      bs.id_company_demand,
      bs.sk_broker_supply,
      bs.sk_broker_demand,
      bs.partner_3p_demand,
      bs.is_3p_supply,
      bs.is_3p_demand,
      bs.is_3p_lead_gen,
      uv.visit_link_type,
      bs.has_3p_access_control,
      CASE WHEN bs.ts_booking_created < eso.ts_offer_created THEN TRUE ELSE FALSE END AS flg_booking_before_offer,
      CASE WHEN bs.ts_visit < eso.ts_offer_created THEN TRUE ELSE FALSE END AS flg_visit_completed_before_offer,
      (
        UNIX_TIMESTAMP(eso.ts_offer_created) - UNIX_TIMESTAMP(bs.ts_booking_created)
      ) / (
        3600
      ) AS hours_booking_to_offer,
      (
        UNIX_TIMESTAMP(eso.ts_offer_created) - UNIX_TIMESTAMP(bs.ts_visit)
      ) / (
        3600
      ) AS hours_visit_to_offer,
      bs.ts_booking_created,
      bs.ts_visit,
      bs.visit_channel,
      eso.ts_offer_created,
      ROW_NUMBER() OVER (PARTITION BY eso.id_sales_flow ORDER BY uv.visit_link_type /* ORDENA PARA PEGAR DO SALESFLOW PRIMEIRO */) AS _w
    FROM datalake_sale_offer.core_sale_offer AS eso
    LEFT JOIN union_visits AS uv
      ON eso.id_sales_flow = uv.id_sales_flow
    LEFT JOIN base_visits AS bs
      ON bs.id_visit = uv.id_visit
  ) AS _t
  WHERE
    _w = 1
), rank_offers AS (
  SELECT
    o.id_offer AS id,
    ROW_NUMBER() OVER (PARTITION BY o.id_buyer ORDER BY o.ts_offer_created) AS buyer_rank_offers,
    ROW_NUMBER() OVER (PARTITION BY o.id_house ORDER BY o.ts_offer_created) AS house_rank_offers
  FROM datalake_sale_offer.core_sale_offer AS o
), sales_flow_details AS (
  SELECT
    id,
    id_sales_flow,
    ts_seller_fup,
    ts_buyer_fup,
    ts_updated
  FROM (
    SELECT
      sfd.id,
      sfd.id_sales_flow,
      sfd.ts_seller_fup,
      sfd.ts_buyer_fup,
      sfd.ts_updated,
      ROW_NUMBER() OVER (PARTITION BY sfd.id_sales_flow ORDER BY sfd.ts_updated DESC) AS _w
    FROM datalake_sales_flow_clean.sales_flow_details AS sfd
  ) AS _t
  WHERE
    _w = 1
), latest_ccv_flow AS (
  SELECT
    id_sales_flow,
    sale_agreement_status,
    is_5a_model
  FROM (
    SELECT
      ccv.id_sales_flow,
      ccv.status AS sale_agreement_status,
      ccv.is_5a_model,
      ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) AS _w,
      ts_updated
    FROM datalake_sales_flow_clean.ccv_flow AS ccv
  ) AS _t
  WHERE
    _w = 1
), latest_sales_flow AS (
  SELECT
    id_sales_flow,
    id_house,
    closing_status,
    sale_agreement_cancellation_reason,
    is_canceled,
    flow_step
  FROM (
    SELECT
      sf.id AS id_sales_flow,
      sf.id_house,
      sf.status_closing AS closing_status,
      sf.closing_canceled_reason AS sale_agreement_cancellation_reason,
      sf.is_canceled,
      sf.flow_step,
      ROW_NUMBER() OVER (PARTITION BY sf.id ORDER BY sf.ts_updated DESC) AS _w,
      sf.id,
      sf.ts_updated
    FROM datalake_sales_flow_clean.sales_flow AS sf
    WHERE
      sf.ts_created < CURRENT_DATE()
  ) AS _t
  WHERE
    _w = 1
), latest_house AS (
  SELECT
    id,
    has_seller_debt_payments,
    house_dilligence_status
  FROM (
    SELECT
      h.id,
      h.has_seller_debt_payments,
      h.house_registration_status AS house_dilligence_status,
      ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY h.ts_updated DESC) AS _w,
      h.ts_updated
    FROM datalake_sales_flow_clean.house AS h
  ) AS _t
  WHERE
    _w = 1
), latest_diligence AS (
  SELECT
    id_diligence,
    id_sales_flow,
    seller_dilligence_status,
    report_dilligence_status
  FROM (
    SELECT
      d.id_diligence,
      d.id_sales_flow,
      d.classification AS seller_dilligence_status,
      d.step AS report_dilligence_status,
      ROW_NUMBER() OVER (PARTITION BY d.id_sales_flow ORDER BY d.ts_updated DESC) AS _w,
      d.ts_updated
    FROM datalake_sales_flow_clean.diligence AS d
  ) AS _t
  WHERE
    _w = 1
), latest_diligence_appointment AS (
  SELECT DISTINCT
    da.id_diligence,
    CONCAT_WS(' - ', COLLECT_SET(da.appointment)) AS diligence_appointment_reason
  FROM datalake_sales_flow_clean.diligence_appointment AS da
  GROUP BY
    da.id_diligence
), cancelation_history AS (
  SELECT
    id,
    is_canceled,
    closing_canceled_reason,
    last_cancelation_status,
    ts_last_canceled,
    ts_updated
  FROM (
    SELECT
      id,
      is_canceled,
      closing_canceled_reason,
      LAG(is_canceled, 1) OVER (PARTITION BY id ORDER BY ts_updated) AS last_cancelation_status,
      LAG(ts_updated, 1) OVER (PARTITION BY id ORDER BY ts_updated) AS ts_last_canceled,
      ts_updated
    FROM datalake_sales_flow_clean.sales_flow_aud
  ) AS _t
  WHERE
    last_cancelation_status IS DISTINCT FROM is_canceled
), rescue_and_cancelation_status AS (
  SELECT
    id_sales_flow,
    closing_canceled_reason,
    is_canceled,
    is_a_rescued_ccv,
    ts_sale_agreement_canceled,
    ts_updated
  FROM (
    SELECT
      id AS id_sales_flow,
      closing_canceled_reason,
      is_canceled,
      CASE
        WHEN is_canceled = FALSE AND last_cancelation_status = TRUE
        THEN TRUE
        ELSE FALSE
      END AS is_a_rescued_ccv,
      ts_last_canceled AS ts_sale_agreement_canceled,
      ts_updated,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w,
      id
    FROM cancelation_history
    WHERE
      NOT ts_last_canceled IS NULL AND NOT closing_canceled_reason IS NULL
  ) AS _t
  WHERE
    _w = 1
), rescue_flow AS (
  SELECT
    id_sales_flow,
    is_a_rescued_ccv,
    ts_sale_agreement_canceled
  FROM rescue_and_cancelation_status
),
visit_from_offer AS (
  WITH agent_related_to_offer AS (
    SELECT
      os.id_offer,
      so.id_sales_flow,
      so.id_house,
      so.id_visit_external,
      so.id_fifty_agent_visit_external,
      os.id_user_agent,
      os.id_user_fifty_agent,
      so.ts_offer_created AS ts_offer_submitted
    FROM
      datalake_sale_offer_flows.offer_specialists as os
    LEFT JOIN
      datalake_sale_offer.core_sale_offer as so
        ON os.id_offer = so.id_offer
  ),
  visit_external AS (
    WITH visit_external_ranked AS (
      SELECT
        arto.id_offer,
        COALESCE(arto.id_visit_external, v.id_visit) AS id_visit_external,
        ROW_NUMBER() OVER (PARTITION BY arto.id_offer ORDER BY v.ts_created DESC) AS _w
      FROM
        agent_related_to_offer AS arto
      JOIN
        datalake_visit.visits AS v
          ON arto.id_house = v.id_house
          AND arto.id_user_agent = v.id_last_associated_agent
          AND arto.ts_offer_submitted >= v.ts_created
          AND v.is_completed
    )
    SELECT
      id_offer,
      id_visit_external
    FROM visit_external_ranked
    WHERE
      _w = 1
  ),
  fifty_visit_external AS (
    WITH fifty_visit_external_ranked AS (
      SELECT
        arto.id_offer,
        COALESCE(arto.id_fifty_agent_visit_external, v.id_visit) AS id_visit_fifty_external,
        ROW_NUMBER() OVER (PARTITION BY arto.id_offer ORDER BY v.ts_created DESC) AS _w
      FROM
        agent_related_to_offer AS arto
      JOIN
        datalake_visit.visits AS v
          ON arto.id_house = v.id_house
          AND arto.id_user_fifty_agent = v.id_last_associated_agent
          AND arto.ts_offer_submitted >= v.ts_created
          AND v.is_completed
    )
    SELECT
      id_offer,
      id_visit_fifty_external
    FROM fifty_visit_external_ranked
    WHERE
      _w = 1
  )
  SELECT
    p.id_offer,
    p.id_visit_external,
    f.id_visit_fifty_external
  FROM
    visit_external AS p
  LEFT JOIN
    fifty_visit_external AS f
      ON p.id_offer = f.id_offer
)
SELECT
  o.id_offer,
  o.id_sales_flow,
  o.id_buyer,
  o.id_house,
  o.id_owner,
  o.id_region,
  o.sale_type,
  r.city_group,
  o.id_agent,
  vfo.id_visit_external,
  vfo.id_visit_fifty_external,
  vo.id_booking,
  o.id_hub AS id_business_unit,
  vo.id_company_supply,
  vo.id_company_demand,
  vo.sk_broker_supply,
  vo.sk_broker_demand,
  vo.is_3p_supply,
  vo.is_3p_demand,
  vo.is_3p_lead_gen,
  vo.has_3p_access_control,
  vo.id_user_secretariat_booking_creator,
  vo.visit_link_type,
  o.flow_type,
  CASE
    WHEN o.flow_type = 'DEAL_MAKING'
    THEN 'DEAL_MAKING' /* Offers que não estão na planilha de trabalho e o Vendas diz ser DM */
    ELSE COALESCE(o.flow_type, 'NOT DEFINED') /* Offers que não estão na planilha de trabalho, não foram atribuidas a um deal maker e possuem offer_flows diferentes de DM no Vendas. */
  END AS offer_flow,
  o.current_payment_method,
  o.planned_payment_method,
  o.payment_model,
  o.credit_model,
  o.tags_from_salesflow,
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
  CAST(NULL AS STRING) AS price_segment,
  CAST(NULL AS BIGINT) AS id_buyer_prospect_type,
  sp.id_user_agent,
  sp.id_user_team_lead,
  sp.id_user_consultant,
  sp.id_consultant,
  sp.id_user_consultant AS id_closing_specialist,
  ccv.sale_agreement_status,
  CASE
    WHEN ccv.is_5a_model IS TRUE
    THEN 'Default 5A CCV'
    WHEN ccv.is_5a_model IS FALSE
    THEN 'Not a 5A CCV Model'
    ELSE 'Unknown'
  END AS ccv_type,
  CASE
    WHEN ccv.is_5a_model IS NULL
    THEN 'Not Answered'
    WHEN ccv.is_5a_model IS FALSE
    THEN 'Not a 5A model'
    WHEN ccv.is_5a_model IS TRUE
    THEN 'Is a 5A model'
    ELSE 'Undefined'
  END AS ccv_model,
  ccv.is_5a_model AS is_ccv_5a_model,
  sf.closing_status,
  sf.sale_agreement_cancellation_reason,
  COALESCE(
    sf.is_canceled,
    CASE
      WHEN NOT o.ts_sale_agreement_signed IS NULL
      THEN CASE WHEN sf.flow_step = 'CANCELED_CCV' THEN TRUE ELSE FALSE END
      ELSE NULL
    END
  ) AS is_ccv_canceled,
  COALESCE(rf.is_a_rescued_ccv, FALSE) AS is_a_rescued_ccv,
  h.house_dilligence_status,
  d.seller_dilligence_status,
  d.report_dilligence_status,
  da.diligence_appointment_reason,
  h.has_seller_debt_payments,
  vo.flg_booking_before_offer,
  vo.flg_visit_completed_before_offer,
  CASE WHEN rk.buyer_rank_offers = 1 THEN TRUE ELSE FALSE END AS is_buyer_first_offer,
  CASE WHEN rk.house_rank_offers = 1 THEN TRUE ELSE FALSE END AS is_house_first_offer,
  vo.ts_booking_created,
  vo.hours_booking_to_offer,
  vo.hours_visit_to_offer,
  CASE
    WHEN CAST(o.ts_offer_created AS DATE) <= CAST(o.ts_offer_accepted AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_offer_accepted AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_submitted_to_offer_accepted,
  CASE
    WHEN CAST(o.ts_offer_created AS DATE) <= CAST(o.ts_sale_agreement_created AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_sale_agreement_created AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_submitted_to_sale_agreement_created,
  CASE
    WHEN CAST(o.ts_offer_created AS DATE) <= CAST(o.ts_offer_discarded AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_offer_discarded AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_submitted_to_offer_dismissed,
  CASE
    WHEN CAST(o.ts_offer_created AS DATE) <= CAST(o.ts_sale_agreement_signed AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_sale_agreement_signed AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_submitted_to_sale_agreement_signed,
  CASE
    WHEN CAST(o.ts_offer_accepted AS DATE) <= CAST(o.ts_sale_agreement_created AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_sale_agreement_created AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_accepted_to_sale_agreement_created,
  CASE
    WHEN CAST(o.ts_offer_accepted AS DATE) <= CAST(o.ts_sale_agreement_signed AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_sale_agreement_signed AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_accepted_to_sale_agreement_signed,
  CASE
    WHEN CAST(o.ts_offer_accepted AS DATE) <= CAST(o.ts_offer_discarded AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_offer_discarded AS DATE)),
      TO_DATE(CAST(o.ts_offer_created AS DATE))
    )
  END AS days_offer_accepted_to_offer_dismissed,
  CASE
    WHEN CAST(o.ts_sale_agreement_created AS DATE) <= CAST(o.ts_sale_agreement_signed AS DATE)
    THEN DATEDIFF(
      TO_DATE(CAST(o.ts_sale_agreement_signed AS DATE)),
      TO_DATE(CAST(o.ts_sale_agreement_created AS DATE))
    )
  END AS days_sale_agreement_created_to_sale_agreement_signed,
  o.ts_offer_created AS ts_offer_submitted,
  o.ts_offer_accepted,
  o.ts_offer_discarded AS ts_offer_dismissed,
  o.ts_offer_canceled,
  o.ts_offer_rescued,
  o.ts_sale_agreement_drafted,
  o.ts_sale_agreement_created,
  o.ts_sale_agreement_signed,
  rf.ts_sale_agreement_canceled AS ts_sale_agreement_canceled,
  sfd.ts_seller_fup,
  sfd.ts_buyer_fup,
  o.ts_updated,
  NOW() AS ts_load
FROM datalake_sale_offer.core_sale_offer AS o
LEFT JOIN visit_offer AS vo
  ON o.id_offer = vo.id_offer
LEFT JOIN datalake_hub_services_clean.business_unit AS bu
  ON o.id_hub = bu.id
LEFT JOIN rank_offers AS rk
  ON rk.id = o.id_offer
LEFT JOIN sales_flow_details AS sfd
  ON sfd.id_sales_flow = o.id_sales_flow
LEFT JOIN datalake_region.region AS r
  ON o.id_region = r.id
LEFT JOIN datalake_sale_offer_flows.offer_specialists AS sp
  ON o.id_offer = sp.id_offer
LEFT JOIN latest_ccv_flow AS ccv
  ON ccv.id_sales_flow = o.id_sales_flow
LEFT JOIN latest_sales_flow AS sf
  ON sf.id_sales_flow = o.id_sales_flow
LEFT JOIN rescue_flow AS rf
  ON rf.id_sales_flow = o.id_sales_flow
LEFT JOIN latest_house AS h
  ON h.id = sf.id_house
LEFT JOIN latest_diligence AS d
  ON d.id_sales_flow = o.id_sales_flow
LEFT JOIN latest_diligence_appointment AS da
  ON da.id_diligence = d.id_diligence
LEFT JOIN visit_from_offer AS vfo
  ON vfo.id_offer = o.id_offer
