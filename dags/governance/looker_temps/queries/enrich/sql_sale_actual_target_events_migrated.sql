WITH sale_supply_targets AS (
  SELECT
    CAST(REPLACE(date, '-', '') AS BIGINT) AS date_,
    city_group,
    campaign,
    mkt_channel,
    mkt_origin,
    mkt_type,
    operacao,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_supply_5a,
    CAST(0 AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    SUM(CAST(NULLIF(REPLACE(CAST(prospects AS STRING), ',', ''), '') AS DOUBLE)) AS prospects_target,
    SUM(CAST(NULLIF(REPLACE(CAST(qualifieds AS STRING), ',', ''), '') AS DOUBLE)) AS qualifieds_target,
    SUM(
      CAST(NULLIF(REPLACE(CAST(available_qualifieds AS STRING), ',', ''), '') AS DOUBLE)
    ) AS available_qualifieds_target,
    SUM(CAST(NULLIF(REPLACE(CAST(opportunities AS STRING), ',', ''), '') AS DOUBLE)) AS opportunities_target,
    SUM(CAST(NULLIF(REPLACE(CAST(first_listings AS STRING), ',', ''), '') AS DOUBLE)) AS first_listings_target
  FROM datalake_gsheets_clean.sale_supply_targets
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), sale_demand_targets AS (
  SELECT
    CAST(REPLACE(date, '-', '') AS BIGINT) AS date_,
    cidade AS city_group,
    NULL AS campaign,
    NULL AS mkt_channel,
    NULL AS mkt_origin,
    NULL AS mkt_type,
    NULL AS operacao,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_supply_5a,
    CAST(0 AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    SUM(CAST(NULLIF(REPLACE(new_buyer_prospect, ',', ''), '') AS DOUBLE)) AS new_buyer_prospect_target,
    SUM(CAST(NULLIF(REPLACE(visit_booked, ',', ''), '') AS DOUBLE)) AS visits_booked_target,
    SUM(CAST(NULLIF(REPLACE(visit_completed, ',', ''), '') AS DOUBLE)) AS visits_completed_target,
    SUM(CAST(NULLIF(REPLACE(offer_sent, ',', ''), '') AS DOUBLE)) AS offer_sent_target,
    SUM(CAST(NULLIF(REPLACE(offer_accepted, ',', ''), '') AS DOUBLE)) AS offer_accepted_target,
    SUM(CAST(NULLIF(REPLACE(ccv, ',', ''), '') AS DOUBLE)) AS sale_agreement_signed_target
  FROM datalake_gsheets_clean.sale_demand_targets
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), sale_closing_targets AS (
  SELECT
    CAST(REPLACE(date, '-', '') AS BIGINT) AS date_,
    city_group,
    NULL AS campaign,
    NULL AS mkt_channel,
    NULL AS mkt_origin,
    NULL AS mkt_type,
    NULL AS operacao,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_supply_5a,
    CAST(0 AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    SUM(CAST(REPLACE(payment_concluded, ',', '') AS DOUBLE)) AS sale_transactions_paid_target,
    SUM(CAST(REPLACE(NULLIF(diligencia_inicio, ''), ',', '') AS DOUBLE)) AS diligence_started_target,
    SUM(CAST(REPLACE(NULLIF(diligencia_fim, ''), ',', '') AS DOUBLE)) AS diligence_finished_target,
    SUM(CAST(REPLACE(NULLIF(credito_inicio, ''), ',', '') AS DOUBLE)) AS credit_started_target,
    SUM(CAST(REPLACE(NULLIF(credito_fim, ''), ',', '') AS DOUBLE)) AS credit_finished_target,
    SUM(CAST(REPLACE(NULLIF(financiamento_inicio, ''), ',', '') AS DOUBLE)) AS financing_started_target,
    SUM(CAST(REPLACE(NULLIF(financiamento_fim, ''), ',', '') AS DOUBLE)) AS financing_finished_target,
    SUM(CAST(REPLACE(NULLIF(cri_inicio, ''), ',', '') AS DOUBLE)) AS house_registry_started_target,
    SUM(CAST(REPLACE(NULLIF(cri_fim, ''), ',', '') AS DOUBLE)) AS house_registry_updated_target,
    SUM(CAST(REPLACE(NULLIF(crn_inicio, ''), ',', '') AS DOUBLE)) AS notes_registry_started_target,
    SUM(CAST(REPLACE(NULLIF(crn_fim, ''), ',', '') AS DOUBLE)) AS notes_registry_ended_target
  FROM datalake_gsheets_clean.sale_payment_concluded_targets
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), sale_ongoing_listing_targets AS (
  SELECT
    CAST(REPLACE(date, '-', '') AS BIGINT) AS date_,
    cidade AS city_group,
    NULL AS campaign,
    NULL AS mkt_channel,
    NULL AS mkt_origin,
    NULL AS mkt_type,
    NULL AS operacao,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_supply_5a,
    CAST(0 AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    SUM(CAST(REPLACE(ongoing_listing, ',', '') AS DOUBLE)) AS ongoing_listing_target
  FROM datalake_gsheets_clean.sale_ongoing_listings_targets
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), sale_ongoing_listing AS (
  SELECT
    CAST(sk_date AS BIGINT) AS date_,
    CASE
      WHEN NOT city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Belo Horizonte', 'Campinas')
      THEN 'Out of coverage area'
      WHEN city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Belo Horizonte', 'Campinas')
      THEN city_group
    END AS city_group,
    NULL AS campaign,
    NULL AS mkt_channel,
    NULL AS mkt_origin,
    NULL AS mkt_type,
    NULL AS operacao,
    is_3p_supply,
    CAST((
      CAST(is_3p_supply AS BOOLEAN) AND NOT CAST(is_3pbh_supply AS BOOLEAN)
    ) AS INT) AS is_3p_supply_5a,
    CAST(is_3pbh_supply AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    SUM(ongoing_listings) AS ongoing_listing
  FROM datamart_sale_ongoing_listing
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), new_buyer_prospect AS (
  SELECT
    CAST(CAST(DATE_FORMAT(DATE(dt_event), 'yyyyMMdd') AS STRING) AS BIGINT) AS date_,
    city_group,
    NULL AS campaign,
    NULL AS mkt_channel,
    NULL AS mkt_origin,
    NULL AS mkt_type,
    NULL AS operacao,
    CAST(0 AS INT) AS is_3p_supply,
    CAST(0 AS INT) AS is_3p_supply_5a,
    CAST(0 AS INT) AS is_3p_supply_bh,
    CAST(0 AS INT) AS is_3p_demand,
    CAST(NULL AS STRING) AS supply_3p_partner,
    CAST(NULL AS STRING) AS demand_3p_partner,
    NULL AS forma_pagamento,
    NULL AS first_origin_demand,
    NULL AS lead_processing_operation,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS hub_visit,
    NULL AS hub_offer,
    COUNT(DISTINCT sk_buyer) AS new_buyer_prospect
  FROM dw_datamarts.sale_performance_marketing_metrics_demand
  WHERE
    buyer_prospect_order = 1
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), sale_events AS (
  SELECT
    CAST(CAST(DATE_FORMAT(DATE(date), 'yyyyMMdd') AS STRING) AS BIGINT) AS date_,
    city_group AS city_group,
    CASE
      WHEN mkt_campaign_context = 'Only Rent'
      THEN 'Rental'
      WHEN mkt_campaign_context = 'Only Sale'
      THEN 'Sale'
      ELSE mkt_campaign_context
    END AS campaign,
    mkt_channel,
    mkt_origin,
    mkt_type,
    is_3p_supply,
    CAST(CAST(is_3p_supply AS BOOLEAN) AND NOT CAST(is_3pbh_supply AS BOOLEAN) AS INT) AS is_3p_supply_5a,
    CAST(is_3pbh_supply AS INT) AS is_3p_supply_bh,
    is_3p_demand,
    supply_3p_partner,
    demand_3p_partner,
    lead_context,
    CASE
      WHEN form_of_payment IN ('À Vista', 'À Vista + FGTS')
      THEN 'À Vista'
      WHEN form_of_payment IN ('Financiado', 'Financiado + FGTS')
      THEN 'Financiado'
    END AS forma_pagamento,
    CASE
      WHEN first_origin_demand = 'booking'
      THEN 'VB+TTA'
      WHEN first_origin_demand = 'offer'
      THEN 'DO'
      WHEN first_origin_demand = 'talk_to_agent'
      THEN 'VB+TTA'
      ELSE 'Sem Info'
    END AS first_origin_demand,
    origin_before_offer,
    origin_after_offer,
    hub_visit,
    hub_offer,
    lead_processing_operation,
    SUM(leads) AS leads,
    SUM(prospects) AS prospects,
    SUM(first_contacts) AS first_contacts,
    SUM(qualifieds) AS qualifieds,
    SUM(available_qualifieds) AS available_qualifieds,
    SUM(opportunities) AS opportunities,
    SUM(first_listings) AS first_listings,
    SUM(tta_started) AS messages_sent_tta,
    SUM(tta_completed) AS registered_agent_supports,
    SUM(visits_booked) AS visits_booked,
    SUM(visits_completed) AS visits_completed,
    SUM(offer_submitted) AS offer_submitted,
    SUM(offer_accepted) AS offer_accepted,
    SUM(ccv_signed) AS sale_agreement_signed,
    SUM(diligence_started_legaut) AS diligence_started_legaut,
    SUM(diligence_ended_legaut) AS diligence_ended_legaut,
    SUM(diligence_started_legal) AS diligence_started_legal,
    SUM(diligence_ended_legal) AS diligence_ended_legal,
    SUM(diligence_ended) AS diligence_ended,
    SUM(credit_sent) AS credit_sent,
    SUM(credit_approved) AS credit_approved,
    SUM(finan_started) AS finan_started,
    SUM(finan_ended) AS finan_ended,
    SUM(payment_concluded) AS sale_transaction_paid,
    SUM(notes_registry_started) AS notes_registry_started,
    SUM(notes_registry_ended) AS notes_registry_ended,
    SUM(matricula_inicio) AS house_registry_initiated,
    SUM(matricula_atualizada) AS house_registry_updated,
    SUM(entrega_chave) AS sale_key_delivery
  FROM dw_datamarts.sale_events_funnel
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20
), datamart_sale_ongoing_listing AS (
  SELECT
    d.date,
    d.sk_date,
    d.weekday_name,
    d.week_start,
    sk_region,
    r.name AS region,
    r.city_name,
    r.city_group,
    l.partner_3p_supply,
    CASE WHEN l.is_3p_supply THEN 1 ELSE 0 END AS is_3p_supply,
    l.partner_3p_supply AS supply_3p_partner,
    CASE WHEN NOT rbh.id_house IS NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
    rbh.partner AS supply_3pbh_partner,
    COUNT(DISTINCT sk_house) AS ongoing_listings,
    COUNT_IF(
      l.consultant_type IN ('CIQ_FULL', 'CIQ_MANAGER')
      AND l.ts_created > l.dt_consultant_started
    ) AS ciq_listing
  FROM dw_sale.fact_daily_ongoing_listing AS ol
  LEFT JOIN dw_sale.dim_listing AS l
    USING (sk_house)
  LEFT JOIN dw_public.dim_region AS r
    USING (sk_region)
  LEFT JOIN dw_public.dim_date AS d
    ON d.sk_date = ol.sk_snapshot_date
  LEFT JOIN datalake_3p.houses_3p_bh AS rbh
    ON rbh.id_house = sk_house
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13
)
SELECT
  TO_TIMESTAMP(CAST(COALESCE(
    COALESCE(COALESCE(COALESCE(COALESCE(se.date_, ol.date_), st.date_), dt.date_), ct.date_),
    og.date_,
    nbp.date_
  ) AS STRING), 'yyyyMMdd') AS date,
  COALESCE(
    COALESCE(
      COALESCE(COALESCE(COALESCE(se.city_group, ol.city_group), st.city_group), dt.city_group),
      ct.city_group
    ),
    og.city_group,
    nbp.city_group
  ) AS city_group,
  COALESCE(se.campaign, st.campaign, ol.campaign, dt.campaign, ct.campaign, og.campaign, nbp.campaign) AS campaign,
  COALESCE(
    se.mkt_channel,
    st.mkt_channel,
    ol.mkt_channel,
    dt.mkt_channel,
    ct.mkt_channel,
    og.mkt_channel,
    nbp.mkt_channel
  ) AS mkt_channel,
  COALESCE(
    se.mkt_origin,
    st.mkt_origin,
    ol.mkt_origin,
    dt.mkt_origin,
    ct.mkt_origin,
    og.mkt_origin,
    nbp.mkt_origin
  ) AS mkt_origin,
  COALESCE(se.mkt_type, st.mkt_type, ol.mkt_type, dt.mkt_type, ct.mkt_type, og.mkt_type, nbp.mkt_type) AS mkt_type,
  COALESCE(
    se.is_3p_supply,
    st.is_3p_supply,
    ol.is_3p_supply,
    dt.is_3p_supply,
    ct.is_3p_supply,
    og.is_3p_supply,
    nbp.is_3p_supply
  ) AS is_3p_supply,
  COALESCE(
    se.is_3p_supply_5a,
    st.is_3p_supply_5a,
    ol.is_3p_supply_5a,
    dt.is_3p_supply_5a,
    ct.is_3p_supply_5a,
    og.is_3p_supply_5a,
    nbp.is_3p_supply_5a
  ) AS is_3p_supply_5a,
  COALESCE(
    se.is_3p_supply_bh,
    st.is_3p_supply_bh,
    ol.is_3p_supply_bh,
    dt.is_3p_supply_bh,
    ct.is_3p_supply_bh,
    og.is_3p_supply_bh,
    nbp.is_3p_supply_bh
  ) AS is_3p_supply_bh,
  COALESCE(
    se.is_3p_demand,
    st.is_3p_demand,
    ol.is_3p_demand,
    dt.is_3p_demand,
    ct.is_3p_demand,
    og.is_3p_demand,
    nbp.is_3p_demand
  ) AS is_3p_demand,
  COALESCE(
    se.supply_3p_partner,
    st.supply_3p_partner,
    ol.supply_3p_partner,
    dt.supply_3p_partner,
    ct.supply_3p_partner,
    og.supply_3p_partner,
    nbp.supply_3p_partner
  ) AS supply_3p_partner,
  COALESCE(
    se.demand_3p_partner,
    st.demand_3p_partner,
    ol.demand_3p_partner,
    dt.demand_3p_partner,
    ct.demand_3p_partner,
    og.demand_3p_partner,
    nbp.demand_3p_partner
  ) AS demand_3p_partner,
  COALESCE(
    se.lead_context,
    st.operacao,
    ol.operacao,
    dt.operacao,
    ct.operacao,
    og.operacao,
    nbp.operacao
  ) AS lead_context,
  COALESCE(
    se.forma_pagamento,
    st.forma_pagamento,
    ol.forma_pagamento,
    dt.forma_pagamento,
    ct.forma_pagamento,
    og.forma_pagamento,
    nbp.forma_pagamento
  ) AS forma_pagemento,
  COALESCE(
    se.first_origin_demand,
    st.first_origin_demand,
    ol.first_origin_demand,
    dt.first_origin_demand,
    ct.first_origin_demand,
    og.first_origin_demand,
    nbp.first_origin_demand
  ) AS first_origin_demand,
  COALESCE(
    se.origin_before_offer,
    st.origin_before_offer,
    ol.origin_before_offer,
    dt.origin_before_offer,
    ct.origin_before_offer,
    og.origin_before_offer,
    nbp.origin_before_offer
  ) AS origin_before_offer,
  COALESCE(
    se.origin_after_offer,
    st.origin_after_offer,
    ol.origin_after_offer,
    dt.origin_after_offer,
    ct.origin_after_offer,
    og.origin_after_offer,
    nbp.origin_after_offer
  ) AS origin_after_offer,
  COALESCE(
    se.hub_visit,
    st.hub_visit,
    ol.hub_visit,
    dt.hub_visit,
    ct.hub_visit,
    og.hub_visit,
    nbp.hub_visit
  ) AS hub_visit,
  COALESCE(
    se.hub_offer,
    st.hub_offer,
    ol.hub_offer,
    dt.hub_offer,
    ct.hub_offer,
    og.hub_offer,
    nbp.hub_offer
  ) AS hub_offer,
  COALESCE(
    se.lead_processing_operation,
    st.lead_processing_operation,
    ol.lead_processing_operation,
    dt.lead_processing_operation,
    ct.lead_processing_operation,
    og.lead_processing_operation,
    nbp.lead_processing_operation
  ) AS lead_processing_operation,
  se.leads,
  se.prospects,
  se.first_contacts,
  se.qualifieds,
  se.available_qualifieds,
  se.opportunities,
  se.first_listings,
  se.messages_sent_tta,
  se.registered_agent_supports,
  se.visits_booked,
  se.visits_completed,
  se.offer_submitted,
  se.offer_accepted,
  se.sale_agreement_signed,
  se.diligence_started_legaut,
  se.diligence_ended_legaut,
  se.diligence_started_legal,
  se.diligence_ended_legal,
  se.diligence_ended,
  se.credit_sent,
  se.credit_approved,
  se.finan_started,
  se.finan_ended,
  se.sale_transaction_paid,
  se.notes_registry_started,
  se.notes_registry_ended,
  se.house_registry_initiated,
  se.house_registry_updated,
  se.sale_key_delivery,
  ol.ongoing_listing,
  nbp.new_buyer_prospect,
  st.prospects_target,
  st.qualifieds_target,
  st.available_qualifieds_target,
  st.opportunities_target,
  st.first_listings_target,
  dt.new_buyer_prospect_target,
  dt.visits_booked_target,
  dt.visits_completed_target,
  dt.offer_sent_target,
  dt.offer_accepted_target,
  dt.sale_agreement_signed_target,
  ct.sale_transactions_paid_target,
  ct.house_registry_started_target,
  ct.house_registry_updated_target,
  ct.diligence_started_target,
  ct.diligence_finished_target,
  ct.credit_started_target,
  ct.credit_finished_target,
  ct.financing_started_target,
  ct.financing_finished_target,
  ct.notes_registry_started_target,
  ct.notes_registry_ended_target,
  og.ongoing_listing_target,
  CURRENT_TIMESTAMP() AS ts_load
FROM sale_events AS se
FULL OUTER JOIN sale_ongoing_listing AS ol
  ON se.date_ = ol.date_
  AND se.city_group = ol.city_group
  AND se.campaign = ol.campaign
  AND se.mkt_channel = ol.mkt_channel
  AND se.mkt_origin = ol.mkt_origin
  AND se.mkt_type = ol.mkt_type
  AND se.lead_context = ol.operacao
  AND se.is_3p_supply = ol.is_3p_supply
  AND se.is_3p_supply_5a = ol.is_3p_supply_5a
  AND se.is_3p_supply_bh = ol.is_3p_supply_bh
  AND se.is_3p_demand = ol.is_3p_demand
  AND se.supply_3p_partner = ol.supply_3p_partner
  AND se.demand_3p_partner = ol.demand_3p_partner
  AND se.forma_pagamento = ol.forma_pagamento
  AND se.lead_processing_operation = ol.lead_processing_operation
  AND se.origin_before_offer = ol.origin_before_offer
  AND se.origin_after_offer = ol.origin_after_offer
  AND se.hub_visit = ol.hub_visit
  AND se.hub_offer = ol.hub_offer
FULL OUTER JOIN sale_supply_targets AS st
  ON se.date_ = st.date_
  AND se.city_group = st.city_group
  AND se.campaign = st.campaign
  AND se.mkt_channel = st.mkt_channel
  AND se.mkt_origin = ol.mkt_origin
  AND se.mkt_type = st.mkt_type
  AND se.lead_context = st.operacao
  AND se.is_3p_supply = st.is_3p_supply
  AND se.is_3p_supply_5a = st.is_3p_supply_5a
  AND se.is_3p_supply_bh = st.is_3p_supply_bh
  AND se.is_3p_demand = st.is_3p_demand
  AND se.supply_3p_partner = st.supply_3p_partner
  AND se.demand_3p_partner = st.demand_3p_partner
  AND se.forma_pagamento = st.forma_pagamento
  AND se.lead_processing_operation = st.lead_processing_operation
  AND se.origin_before_offer = st.origin_before_offer
  AND se.origin_after_offer = st.origin_after_offer
  AND se.hub_visit = st.hub_visit
  AND se.hub_offer = st.hub_offer
FULL OUTER JOIN sale_demand_targets AS dt
  ON se.date_ = dt.date_
  AND se.city_group = dt.city_group
  AND se.campaign = dt.campaign
  AND se.mkt_channel = dt.mkt_channel
  AND se.mkt_origin = ol.mkt_origin
  AND se.mkt_type = dt.mkt_type
  AND se.lead_context = dt.operacao
  AND se.is_3p_supply = dt.is_3p_supply
  AND se.is_3p_supply_5a = dt.is_3p_supply_5a
  AND se.is_3p_supply_bh = dt.is_3p_supply_bh
  AND se.is_3p_demand = dt.is_3p_demand
  AND se.supply_3p_partner = dt.supply_3p_partner
  AND se.demand_3p_partner = dt.demand_3p_partner
  AND se.forma_pagamento = dt.forma_pagamento
  AND se.lead_processing_operation = dt.lead_processing_operation
  AND se.origin_before_offer = dt.origin_before_offer
  AND se.origin_after_offer = dt.origin_after_offer
  AND se.hub_visit = dt.hub_visit
  AND se.hub_offer = dt.hub_offer
FULL OUTER JOIN sale_closing_targets AS ct
  ON se.date_ = ct.date_
  AND se.city_group = ct.city_group
  AND se.campaign = ct.campaign
  AND se.mkt_channel = ct.mkt_channel
  AND se.mkt_origin = ol.mkt_origin
  AND se.mkt_type = ct.mkt_type
  AND se.lead_context = ct.operacao
  AND se.is_3p_supply = ct.is_3p_supply
  AND se.is_3p_supply_5a = ct.is_3p_supply_5a
  AND se.is_3p_supply_bh = ct.is_3p_supply_bh
  AND se.is_3p_demand = ct.is_3p_demand
  AND se.supply_3p_partner = ct.supply_3p_partner
  AND se.demand_3p_partner = ct.demand_3p_partner
  AND se.forma_pagamento = ct.forma_pagamento
  AND se.lead_processing_operation = ct.lead_processing_operation
  AND se.origin_before_offer = ct.origin_before_offer
  AND se.origin_after_offer = ct.origin_after_offer
  AND se.hub_visit = ct.hub_visit
  AND se.hub_offer = ct.hub_offer
FULL OUTER JOIN sale_ongoing_listing_targets AS og
  ON se.date_ = og.date_
  AND se.city_group = og.city_group
  AND se.campaign = og.campaign
  AND se.mkt_channel = og.mkt_channel
  AND se.mkt_origin = ol.mkt_origin
  AND se.mkt_type = og.mkt_type
  AND se.lead_context = og.operacao
  AND se.is_3p_supply = og.is_3p_supply
  AND se.is_3p_supply_5a = og.is_3p_supply_5a
  AND se.is_3p_supply_bh = og.is_3p_supply_bh
  AND se.is_3p_demand = og.is_3p_demand
  AND se.supply_3p_partner = og.supply_3p_partner
  AND se.demand_3p_partner = og.demand_3p_partner
  AND se.forma_pagamento = og.forma_pagamento
  AND se.lead_processing_operation = og.lead_processing_operation
  AND se.origin_before_offer = og.origin_before_offer
  AND se.origin_after_offer = og.origin_after_offer
  AND se.hub_visit = og.hub_visit
  AND se.hub_offer = og.hub_offer
FULL OUTER JOIN new_buyer_prospect AS nbp
  ON se.date_ = nbp.date_
  AND se.city_group = nbp.city_group
  AND se.campaign = nbp.campaign
  AND se.mkt_channel = nbp.mkt_channel
  AND se.mkt_origin = nbp.mkt_origin
  AND se.mkt_type = nbp.mkt_type
  AND se.lead_context = nbp.operacao
  AND se.is_3p_supply = nbp.is_3p_supply
  AND se.is_3p_supply_5a = nbp.is_3p_supply_5a
  AND se.is_3p_supply_bh = nbp.is_3p_supply_bh
  AND se.is_3p_demand = nbp.is_3p_demand
  AND se.supply_3p_partner = nbp.supply_3p_partner
  AND se.demand_3p_partner = nbp.demand_3p_partner
  AND se.forma_pagamento = nbp.forma_pagamento
  AND se.lead_processing_operation = nbp.lead_processing_operation
  AND se.origin_before_offer = nbp.origin_before_offer
  AND se.origin_after_offer = nbp.origin_after_offer
  AND se.hub_visit = nbp.hub_visit
  AND se.hub_offer = nbp.hub_offer