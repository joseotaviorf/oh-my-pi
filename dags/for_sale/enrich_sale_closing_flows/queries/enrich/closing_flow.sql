WITH last_method_change AS (
  SELECT
    soa.id AS id_offer,
    GET_JSON_OBJECT(soa.original_message, '$.paymentOptions.paymentMethod') AS payment_method_original,
    GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.paymentMethod') AS payment_method_updated,
    ROW_NUMBER() OVER (PARTITION BY soa.id ORDER BY MAX(soa.ts_updated) DESC) AS ROW,
    CAST(MAX(soa.ts_updated) AS DATE) AS dt_payment_method_change
  FROM datalake_firestore_clean.sale_offer AS soa
  WHERE
    GET_JSON_OBJECT(soa.original_message, '$.paymentOptions.paymentMethod') <> GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.paymentMethod')
  GROUP BY
    1,
    2,
    3
), payments_method_change AS (
  SELECT
    id_offer,
    payment_method_original,
    payment_method_updated,
    dt_payment_method_change
  FROM last_method_change
  WHERE
    ROW = 1
), diligence AS (
  SELECT
    id_diligence,
    id_sales_flow,
    dt_legal_analysis_ended
  FROM (
    SELECT
      id_diligence_aud AS id_diligence,
      id_sales_flow,
      CAST(ts_buyer_seller_ended AS DATE) AS dt_legal_analysis_ended,
      ROW_NUMBER() OVER (PARTITION BY id_diligence_aud ORDER BY ts_updated) AS _w,
      id_diligence_aud,
      ts_updated
    FROM datalake_sales_flow_clean.diligence_aud
    WHERE
      NOT ts_buyer_seller_ended IS NULL
  ) AS _t
  WHERE
    1 = _w
), mortgage AS (
  SELECT
    id_mortgage,
    id_sales_flow,
    bank,
    status,
    credit_model,
    credit_status,
    dt_bank_started,
    dt_credit_started,
    dt_credit_ended,
    dt_credit_analysis_ended,
    dt_started,
    dt_ended,
    dt_seller_paid
  FROM (
    SELECT
      mg.id_mortgage_aud AS id_mortgage,
      mg.id_sales_flow,
      mg.bank,
      mg.status,
      mg.credit_model,
      mg.credit_status,
      mg.dt_bank_started,
      mg.dt_credit_started,
      mg.dt_credit_ended,
      CAST(mg.dt_credit_ended AS DATE) AS dt_credit_analysis_ended,
      mg.dt_started,
      mg.dt_ended,
      CAST(mg.ts_seller_paid AS DATE) AS dt_seller_paid,
      ROW_NUMBER() OVER (PARTITION BY mg.id_mortgage_aud ORDER BY mg.ts_updated DESC) AS _w,
      mg.id_mortgage_aud,
      mg.ts_updated
    FROM datalake_sales_flow_clean.mortgage_aud AS mg
    WHERE
      NOT mg.dt_credit_ended IS NULL
  ) AS _t
  WHERE
    _w = 1
), notary AS (
  SELECT
    id_notary,
    id_sales_flow,
    status,
    dt_started,
    dt_ended,
    dt_buyer_received_keys
  FROM (
    SELECT
      n.id_notary,
      n.id_sales_flow,
      n.status,
      CAST(n.ts_started AS DATE) AS dt_started,
      CAST(n.ts_ended AS DATE) AS dt_ended,
      CAST(n.ts_buyer_received_keys AS DATE) AS dt_buyer_received_keys,
      ROW_NUMBER() OVER (PARTITION BY n.id_notary ORDER BY n.ts_updated DESC) AS _w,
      n.ts_updated
    FROM datalake_sales_flow_clean.notary AS n
  ) AS _t
  WHERE
    _w = 1
), payment_dates AS (
  SELECT
    o.id_offer,
    o.id_sales_flow,
    so.current_payment_method,
    ms.dt_occurence,
    o.payment_model,
    pm.payment_method_original,
    pm.payment_method_updated,
    pm.dt_payment_method_change,
    COALESCE(di.dt_legal_analysis_ended, m.dt_legal_analysis_ended) AS dt_legal_analysis_ended,
    COALESCE(mg.dt_credit_analysis_ended, m.dt_credit_analysis_ended) AS dt_credit_analysis_ended,
    COALESCE(mg.dt_seller_paid, m.dt_sale_transacton_paid) AS dt_sale_transacton_paid
  FROM datalake_sale_offer_flows.sale_offer_flows AS o
  INNER JOIN datalake_sale_offer.sale_offer AS so
    ON so.id_offer = o.id_offer
  INNER JOIN datalake_monopoly.sale AS ms
    ON ms.id_offer = o.id_offer AND NOT ms.dt_occurence IS NULL
  LEFT JOIN payments_method_change AS pm
    ON pm.id_offer = o.id_offer
  LEFT JOIN mortgage AS mg
    ON mg.id_sales_flow = o.id_sales_flow
  LEFT JOIN diligence AS di
    ON di.id_sales_flow = o.id_sales_flow
  LEFT JOIN datalake_firestore.monday AS m
    ON o.id_offer = m.id_offer
), payment_rule AS (
  SELECT
    id_offer,
    id_sales_flow,
    current_payment_method,
    dt_occurence,
    payment_method_original,
    payment_method_updated,
    dt_payment_method_change,
    dt_legal_analysis_ended,
    dt_credit_analysis_ended,
    CASE
      WHEN payment_model = 'BROKERAGE_TERM' AND NOT dt_occurence IS NULL
      THEN dt_occurence
      WHEN current_payment_method LIKE 'FINANCED%'
      AND NOT CONCAT(dt_occurence, dt_legal_analysis_ended, dt_credit_analysis_ended) IS NULL
      AND dt_payment_method_change IS NULL
      THEN CAST(GREATEST(dt_occurence, dt_legal_analysis_ended, dt_credit_analysis_ended) AS DATE)
      WHEN current_payment_method LIKE 'CASH%'
      AND NOT CONCAT(dt_occurence, dt_legal_analysis_ended) IS NULL
      THEN CAST(GREATEST(dt_occurence, dt_legal_analysis_ended) AS DATE)
      WHEN current_payment_method LIKE 'FINANCED%'
      AND payment_method_updated LIKE 'FINANCED%'
      AND NOT CONCAT(dt_occurence, dt_legal_analysis_ended) IS NULL
      AND NOT dt_payment_method_change IS NULL
      THEN CASE
        WHEN dt_legal_analysis_ended <= dt_payment_method_change
        AND payment_method_original LIKE 'CASH%'
        THEN CAST(GREATEST(dt_occurence, dt_legal_analysis_ended) AS DATE)
        WHEN NOT CONCAT(dt_occurence, dt_legal_analysis_ended, dt_credit_analysis_ended) IS NULL
        THEN CAST(GREATEST(dt_occurence, dt_legal_analysis_ended, dt_credit_analysis_ended) AS DATE)
      END
      ELSE NULL
    END AS dt_payment_allowed,
    dt_sale_transacton_paid
  FROM payment_dates
), data_sources AS (
  SELECT
    so.id_offer,
    so.id_buyer,
    so.id_owner,
    so.id_house,
    so.id_company_supply,
    cs.uuid_company AS uuid_company_supply,
    so.id_company_demand,
    cb_demand.sk_broker AS sk_broker_demand,
    COALESCE('ID_VENDAS_' || sof.id_consultant, 'ID_MONDAY_' || m.id_closing_specialist) AS id_closing_specialist,
    COALESCE('ID_VENDAS_' || sof.id_legal_risk_analyst, 'ID_MONDAY_' || m.id_legal_risk_analyst) AS id_legal_risk_analyst,
    COALESCE('ID_VENDAS_' || sof.id_pre_specialist, 'ID_MONDAY_' || m.id_pre_specialist) AS id_pre_specialist,
    COALESCE('ID_VENDAS_' || sof.id_post_specialist, 'ID_MONDAY_' || m.id_post_specialist) AS id_post_specialist,
    COALESCE(
      'ID_VENDAS_' || sof.id_start_financing_specialist,
      'ID_MONDAY_' || m.id_start_financing_specialist
    ) AS id_start_financing_specialist,
    COALESCE(
      'ID_VENDAS_' || sof.id_follow_up_financing_specialist,
      'ID_MONDAY_' || m.id_follow_up_financing_specialist
    ) AS id_follow_up_financing_specialist,
    COALESCE(
      'ID_VENDAS_' || sof.id_end_financing_specialist,
      'ID_MONDAY_' || m.id_end_financing_specialist
    ) AS id_end_financing_specialist,
    COALESCE('ID_VENDAS_' || sof.id_credit_specialist, 'ID_MONDAY_' || m.id_credit_specialist) AS id_credit_specialist,
    COALESCE(
      'ID_VENDAS_' || sof.id_notes_registry_specialist,
      'ID_MONDAY_' || m.id_notes_registry_specialist
    ) AS id_notes_registry_specialist,
    COALESCE(
      'ID_VENDAS_' || sof.id_real_estate_register_specialist,
      'ID_MONDAY_' || m.id_real_estate_register_specialist
    ) AS id_real_estate_register_specialist,
    cs.company_name AS partner_3p_supply,
    cd.company_name AS partner_3p_demand,
    so.is_3p_supply,
    so.is_3p_demand,
    so.is_3p_lead_gen,
    so.has_3p_access_control,
    CAST(so.ts_sale_agreement_created AS DATE) AS dt_sale_agreement_created,
    so.ts_sale_agreement_signed AS dt_sale_agreement_signed,
    CAST(sof.dt_sale_agreement_cancelled AS DATE) AS dt_sale_agreement_cancelled,
    COALESCE(
      sof.dt_onboarding_ended,
      CASE
        WHEN CAST(so.ts_offer_submitted AS DATE) > '2022-04-12'
        THEN NULL
        ELSE m.dt_onboarding_ended
      END
    ) AS dt_onboarding_ended,
    COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended) AS dt_legal_analysis_ended,
    COALESCE(sof.dt_legaut_analysis_started, m.dt_legaut_analysis_started) AS dt_legaut_analysis_started,
    COALESCE(sof.dt_legaut_analysis_ended, m.dt_legaut_analysis_ended) AS dt_legaut_analysis_ended,
    COALESCE(sof.dt_legal_risk_started, m.dt_legal_risk_started) AS dt_legal_risk_started,
    COALESCE(sof.dt_legal_risk_ended, m.dt_legal_risk_ended) AS dt_legal_risk_ended,
    COALESCE(sof.dt_bank_legal_analysis_started, m.dt_bank_legal_analysis_started) AS dt_bank_legal_analysis_started,
    COALESCE(sof.dt_credit_analysis_started, m.dt_credit_analysis_started) AS dt_credit_analysis_started,
    COALESCE(sof.dt_credit_analysis_ended, m.dt_credit_analysis_ended) AS dt_credit_analysis_ended,
    COALESCE(sof.dt_financing_started, m.dt_financing_started) AS dt_financing_started,
    COALESCE(sof.dt_financing_ended, m.dt_financing_ended) AS dt_financing_ended,
    COALESCE(sof.dt_notes_registry_started, m.dt_notes_registry_started) AS dt_notes_registry_started,
    COALESCE(sof.dt_notes_registry_ended, m.dt_notes_registry_ended) AS dt_notes_registry_ended,
    COALESCE(n.dt_started, m.dt_house_registry_started) AS dt_house_registry_started,
    COALESCE(n.dt_ended, m.dt_house_registry_ended) AS dt_house_registry_ended,
    COALESCE(sof.dt_sale_key_delivered, m.dt_sale_key_delivered) AS dt_sale_key_delivered,
    pr.dt_sale_transacton_paid,
    sof.dt_sale_agreement_rescued AS dt_sale_agreement_rescued,
    pr.dt_payment_allowed,
    sof.dt_diligence_buyer_sent_at,
    sof.dt_diligence_seller_sent_at,
    ms.dt_occurence AS dt_down_payment,
    so.ts_updated
  FROM datalake_sale_offer.sale_offer AS so
  LEFT JOIN notary AS n
    ON so.id_sales_flow = n.id_sales_flow
  LEFT JOIN datalake_firestore.monday AS m
    ON so.id_offer = m.id_offer
  LEFT JOIN datalake_sale_offer_flows.sale_offer_flows AS sof
    ON so.id_offer = sof.id_offer
  LEFT JOIN datalake_monopoly.sale AS ms
    ON ms.id_offer = so.id_offer
  LEFT JOIN payment_rule AS pr
    ON pr.id_offer = so.id_offer
  LEFT JOIN datalake_company.company_sks AS cs
    ON so.id_company_supply = cs.sk_company
  LEFT JOIN datalake_company.company_sks AS cd
    ON so.id_company_demand = cd.sk_company
  LEFT JOIN core_brokers.brokers AS cb_demand
    ON cd.uuid_company = cb_demand.uuid_company
  WHERE
    NOT so.ts_sale_agreement_signed IS NULL
)
SELECT
  id_offer,
  id_buyer,
  id_owner,
  id_house,
  id_company_supply,
  uuid_company_supply,
  id_company_demand,
  sk_broker_demand,
  id_closing_specialist,
  id_legal_risk_analyst,
  id_pre_specialist,
  id_post_specialist,
  id_start_financing_specialist,
  id_follow_up_financing_specialist,
  id_end_financing_specialist,
  id_credit_specialist,
  id_notes_registry_specialist,
  id_real_estate_register_specialist,
  partner_3p_supply,
  partner_3p_demand,
  is_3p_supply,
  is_3p_demand,
  is_3p_lead_gen,
  has_3p_access_control,
  DATEDIFF(TO_DATE(dt_legaut_analysis_started), TO_DATE(dt_sale_agreement_created)) AS days_sale_agreement_created_to_legaut_analysis_started,
  DATEDIFF(TO_DATE(dt_house_registry_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_house_registry_started,
  DATEDIFF(TO_DATE(dt_house_registry_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_house_registry_ended,
  DATEDIFF(TO_DATE(dt_sale_agreement_cancelled), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_sale_agreement_cancelled,
  DATEDIFF(TO_DATE(dt_onboarding_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_onboarding_ended,
  DATEDIFF(TO_DATE(dt_credit_analysis_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_credit_analysis_started,
  DATEDIFF(TO_DATE(dt_credit_analysis_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_credit_analysis_ended,
  DATEDIFF(TO_DATE(dt_financing_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_financing_started,
  DATEDIFF(TO_DATE(dt_financing_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_financing_ended,
  DATEDIFF(TO_DATE(dt_notes_registry_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_notes_registry_started,
  DATEDIFF(TO_DATE(dt_notes_registry_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_notes_registry_ended,
  DATEDIFF(TO_DATE(dt_legaut_analysis_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_legaut_analysis_started,
  DATEDIFF(TO_DATE(dt_legaut_analysis_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_legaut_analysis_ended,
  DATEDIFF(TO_DATE(dt_legal_risk_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_legal_risk_ended,
  DATEDIFF(TO_DATE(dt_bank_legal_analysis_started), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_bank_legal_analysis_started,
  DATEDIFF(TO_DATE(dt_legal_analysis_ended), TO_DATE(dt_sale_agreement_signed)) AS days_sale_agreement_signed_to_legal_analysis_ended,
  DATEDIFF(TO_DATE(dt_legal_risk_ended), TO_DATE(dt_legal_risk_started)) AS days_legal_risk_started_to_legal_risk_ended,
  DATEDIFF(TO_DATE(dt_legal_analysis_ended), TO_DATE(dt_legal_risk_ended)) AS days_legal_risk_ended_to_legal_analysis_ended,
  DATEDIFF(TO_DATE(dt_legaut_analysis_ended), TO_DATE(dt_legaut_analysis_started)) AS days_legaut_analysis_started_to_legaut_analysis_ended,
  DATEDIFF(TO_DATE(dt_legal_risk_ended), TO_DATE(dt_legaut_analysis_ended)) AS days_legaut_analysis_ended_to_legal_risk_ended,
  DATEDIFF(TO_DATE(dt_notes_registry_ended), TO_DATE(dt_legal_analysis_ended)) AS days_legal_analysis_ended_notes_registry_ended,
  DATEDIFF(TO_DATE(dt_bank_legal_analysis_started), TO_DATE(dt_legal_analysis_ended)) AS days_legal_analysis_ended_to_bank_legal_analysis_started,
  DATEDIFF(TO_DATE(dt_financing_ended), TO_DATE(dt_bank_legal_analysis_started)) AS days_bank_legal_analysis_started_to_financing_ended,
  DATEDIFF(TO_DATE(dt_house_registry_started), TO_DATE(dt_bank_legal_analysis_started)) AS days_bank_legal_analysis_started_to_house_registry_started,
  DATEDIFF(TO_DATE(dt_credit_analysis_ended), TO_DATE(dt_credit_analysis_started)) AS days_credit_analysis_started_to_credit_analysis_ended,
  DATEDIFF(TO_DATE(dt_bank_legal_analysis_started), TO_DATE(dt_credit_analysis_ended)) AS days_credit_analysis_ended_to_bank_legal_analysis_started,
  DATEDIFF(TO_DATE(dt_financing_started), TO_DATE(dt_credit_analysis_ended)) AS days_credit_analysis_ended_to_financing_started,
  DATEDIFF(TO_DATE(dt_bank_legal_analysis_started), TO_DATE(dt_financing_started)) AS days_financing_started_to_bank_legal_analysis_started,
  DATEDIFF(TO_DATE(dt_financing_ended), TO_DATE(dt_financing_started)) AS days_financing_started_to_financing_ended,
  DATEDIFF(TO_DATE(dt_house_registry_ended), TO_DATE(dt_financing_ended)) AS days_financing_ended_to_house_registry_ended,
  DATEDIFF(TO_DATE(dt_house_registry_started), TO_DATE(dt_financing_ended)) AS days_financing_ended_to_house_registry_started,
  DATEDIFF(TO_DATE(dt_notes_registry_ended), TO_DATE(dt_notes_registry_started)) AS days_notes_registry_started_to_notes_registry_ended,
  DATEDIFF(TO_DATE(dt_house_registry_ended), TO_DATE(dt_house_registry_started)) AS days_house_registry_started_to_house_registry_ended,
  DATEDIFF(TO_DATE(dt_house_registry_started), TO_DATE(dt_notes_registry_ended)) AS days_notes_registry_ended_to_house_registry_started,
  DATEDIFF(TO_DATE(dt_house_registry_ended), TO_DATE(dt_notes_registry_ended)) AS days_notes_registry_ended_to_house_registry_ended,
  DATEDIFF(TO_DATE(dt_sale_key_delivered), TO_DATE(dt_house_registry_ended)) AS days_house_registry_ended_to_sale_key_delivered,
  DATEDIFF(TO_DATE(dt_sale_transacton_paid), TO_DATE(dt_house_registry_ended)) AS days_house_registry_ended_to_sale_transaction_paid,
  dt_sale_agreement_created,
  dt_sale_agreement_signed,
  dt_sale_agreement_cancelled,
  dt_sale_agreement_rescued,
  dt_onboarding_ended,
  dt_legal_analysis_ended,
  dt_legaut_analysis_started,
  dt_legaut_analysis_ended,
  dt_legal_risk_started,
  dt_legal_risk_ended,
  dt_bank_legal_analysis_started,
  dt_credit_analysis_started,
  dt_credit_analysis_ended,
  dt_financing_started,
  dt_financing_ended,
  dt_notes_registry_started,
  dt_notes_registry_ended,
  dt_house_registry_started,
  dt_house_registry_ended,
  dt_sale_key_delivered,
  dt_sale_transacton_paid,
  dt_diligence_buyer_sent_at,
  dt_diligence_seller_sent_at,
  dt_payment_allowed,
  dt_down_payment,
  ts_updated,
  CURRENT_TIMESTAMP() AS ts_load
FROM data_sources