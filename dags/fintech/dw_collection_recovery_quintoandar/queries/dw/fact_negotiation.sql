WITH
original_invoices AS (
  SELECT
    b.sk_negotiation,
    d.id_contract,
    MIN(d.dt_due) AS dt_due_invoice_anchor,
    COUNT(DISTINCT d.id_invoice) AS total_invoices_negotiated
  FROM dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
  INNER JOIN dw_collection_recovery_quintoandar.fact_debt AS d
    ON d.sk_debt = b.sk_debt
  GROUP BY 1,2
),
installments_data AS (
  SELECT
    id_negotiation,
    sk_contract,
    payment_method AS promisse_payment_method,
    main_amount AS down_payment_original_amount,
    amount_to_pay AS down_payment_amount,
    net_amount AS down_payment_net_amount,
    dt_paid AS dt_down_payment
  FROM dw_collection_recovery_quintoandar.fact_negotiation_installment
  WHERE installment_number = 1
),
renegotiation AS (
  SELECT
    CAST(i.id_negotiation AS BIGINT) AS id_negotiation,
    i.id_contract,
    IF(COUNT(DISTINCT d.id_negotiation) > 0, TRUE, FALSE) AS has_been_renegotiated
  FROM datalake_debt_recovery.installment AS i
  LEFT JOIN datalake_trato_feito_clean.accounting_installment AS ai
    ON ai.id_installment = i.id
  LEFT JOIN datalake_trato_feito_clean.debt AS d
    ON ai.id_external = d.id_external
  GROUP BY 1,2
),
paschoalotto_operator AS (
  SELECT DISTINCT
    d.id_contract_quintoandar AS id_contract,
    CAST(ad.id_installment AS BIGINT) AS id_negotiation,
    CONCAT('PASC_',UPPER(u.login_name)) AS id_operator,
    DATE(ad.dt_emission) AS dt_promisse
  FROM datalake_paschoalotto_clean.agreement_detail AS ad
  LEFT JOIN datalake_paschoalotto_clean.contract AS c
    ON ad.id_contract = c.id_contract
  LEFT JOIN datalake_paschoalotto_clean.debt AS d
    ON ad.id_contract = d.id_contract
  LEFT JOIN datalake_paschoalotto_clean.user AS u
      ON ad.id_user = u.id_user
  QUALIFY ROW_NUMBER() OVER(PARTITION BY d.id_contract_quintoandar, ad.id_installment ORDER BY ad.ts_update DESC) = 1
),
calculations AS (
  SELECT
    CONCAT(COALESCE(CAST(u.id_contract AS BIGINT), 0), CAST(u.id_negotiation AS STRING)) AS sk_negotiation,
    CAST(u.id_contract AS BIGINT) AS sk_contract,
    u.id_debtor AS sk_debtor,
    COALESCE(po.id_operator, u.id_operator) AS sk_operator,
    CAST(u.id_negotiation AS STRING) AS id_negotiation,
    u.id_negotiation_trato_feito,
    u.id_manager_authorized,
    u.id_campaign,
    u.creditor,
    u.source,
    u.is_not_standard_negotiation,
    u.not_standard_reason,
    u.agreement_type,
    u.agreement_type_description,
    u.advisory,
    u.origin_agreement,
    u.campaign_status,
    u.broken_reason,
    u.negotiation_status,
    CASE
        WHEN COALESCE(i.dt_down_payment,u.dt_down_payment) IS NULL
          AND u.negotiation_status = "started" THEN "PROMESSA"
        WHEN COALESCE(i.dt_down_payment,u.dt_down_payment) IS NULL
          AND u.negotiation_status = "canceled" THEN "PROMESSA QUEBRADA"
        WHEN COALESCE(i.dt_down_payment,u.dt_down_payment) IS NOT NULL
          AND oi.total_invoices_negotiated >= 1 AND u.number_of_installments > 1 THEN "ACORDO"
        WHEN COALESCE(i.dt_down_payment,u.dt_down_payment) IS NOT NULL
          AND oi.total_invoices_negotiated > 1 AND u.number_of_installments = 1 THEN "QUITAÇÃO"
        WHEN COALESCE(i.dt_down_payment,u.dt_down_payment) IS NOT NULL
          AND oi.total_invoices_negotiated = 1 AND u.number_of_installments = 1 THEN "SUBSTITUIÇÃO"
      END AS negotiation_classification,
    CASE
      WHEN UPPER(COALESCE(i.promisse_payment_method, u.promisse_payment_method)) IN ("CREDIT-CARD", "CARTÃO", "CARTÃO DE CRÉDITO") THEN "CARTÃO DE CRÉDITO"
      ELSE UPPER(COALESCE(i.promisse_payment_method, u.promisse_payment_method))
    END AS promisse_payment_method,
    u.payment_method,
    u.is_renegotiation,
    r.has_been_renegotiated,
    CASE
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 0 THEN "Current"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 30  THEN "1-30"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 60  THEN "31-60"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 90  THEN "61-90"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 120 THEN "91-120"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) <= 180 THEN "121-180"
      WHEN DATEDIFF(u.dt_promisse, oi.dt_due_invoice_anchor) IS NULL THEN NULL
      ELSE "over 180"
    END AS delay_contamined_range,
    oi.total_invoices_negotiated,
    u.number_of_installments,
    u.paid_installments,
    u.breached_installments,
    u.original_debt_amount,
    u.fine_fee_amount,
    u.interest_fee_amount,
    u.credit_card_fee_amount,
    u.installment_eviction_costs,
    u.installment_lawyers_fee,
    u.total_debt_amount,
    CASE
      WHEN u.total_discount_amount = 0
         AND (source LIKE "%Recupera%" OR source LIKE "%Migração%")
         AND u.negotiated_amount < u.total_debt_amount
        THEN u.total_debt_amount - u.negotiated_amount
      ELSE u.total_discount_amount
    END AS total_discount_amount,
    u.discount_to_original_amount,
    u.discount_to_fees_amount,
    u.discount_to_credit_fee_amount,
    u.negotiated_amount,
    i.down_payment_original_amount,
    COALESCE(i.down_payment_amount, u.down_payment_amount) AS down_payment_amount,
    i.down_payment_net_amount,
    IF(COALESCE(i.dt_down_payment,u.dt_down_payment) IS NOT NULL, i.down_payment_net_amount, 0) AS down_payment_net_amount_paid,
    u.paid_amount,
    oi.dt_due_invoice_anchor,
    u.dt_promisse,
    u.dt_due_promisse,
    DATE(IF(u.negotiation_status != "finished", u.dt_cancellation, NULL)) AS dt_cancellation,
    COALESCE(i.dt_down_payment,u.dt_down_payment) AS dt_down_payment,
    u.dt_paid_all_installments,
    u.dt_expected_ending
  FROM datalake_collections_quintoandar.negotiation AS u
  LEFT JOIN paschoalotto_operator AS po
    ON
      UPPER(u.id_operator) LIKE "%PASCH%"
      AND po.id_contract = u.id_contract
      AND po.id_negotiation = u.id_negotiation
      AND po.dt_promisse = u.dt_promisse
  LEFT JOIN renegotiation AS r
    ON u.id_negotiation = r.id_negotiation
      AND u.id_negotiation = r.id_contract
  LEFT JOIN original_invoices AS oi
    ON oi.sk_negotiation = CONCAT(CAST(u.id_contract AS BIGINT),u.id_negotiation)
  LEFT JOIN installments_data AS i
    ON u.id_negotiation = i.id_negotiation
    AND u.id_contract = sk_contract
),
calculate_discounts AS (
  SELECT
    sk_negotiation,
    sk_contract,
    sk_debtor,
    sk_operator,
    id_negotiation,
    id_negotiation_trato_feito,
    id_manager_authorized,
    id_campaign,
    creditor,
    source,
    is_not_standard_negotiation,
    not_standard_reason,
    agreement_type,
    agreement_type_description,
    advisory,
    origin_agreement,
    campaign_status,
    broken_reason,
    negotiation_status,
    negotiation_classification,
    promisse_payment_method,
    payment_method,
    is_renegotiation,
    has_been_renegotiated,
    delay_contamined_range,
    total_invoices_negotiated,
    number_of_installments,
    paid_installments,
    breached_installments,
    original_debt_amount,
    fine_fee_amount,
    interest_fee_amount,
    credit_card_fee_amount,
    installment_eviction_costs,
    installment_lawyers_fee,
    total_debt_amount,
    total_discount_amount,
    COALESCE(discount_to_fees_amount,
      CASE
        WHEN total_discount_amount >= (fine_fee_amount + interest_fee_amount)
          THEN (fine_fee_amount + interest_fee_amount)
        ELSE total_discount_amount
      END) AS discount_to_fees_amount,
    COALESCE(discount_to_credit_fee_amount,
      CASE
        WHEN credit_card_fee_amount != 0 AND total_discount_amount = (fine_fee_amount + interest_fee_amount + credit_card_fee_amount) THEN credit_card_fee_amount
        ELSE 0
      END) AS discount_to_credit_fee_amount,
    COALESCE(discount_to_original_amount,
      CASE
        WHEN credit_card_fee_amount != 0 AND total_discount_amount = (fine_fee_amount + interest_fee_amount + credit_card_fee_amount) THEN total_discount_amount - (fine_fee_amount + interest_fee_amount + credit_card_fee_amount)
        WHEN total_discount_amount >= (fine_fee_amount + interest_fee_amount) THEN total_discount_amount - (fine_fee_amount + interest_fee_amount)
        ELSE 0
      END) AS discount_to_original_amount,
    negotiated_amount,
    down_payment_original_amount,
    down_payment_amount,
    down_payment_net_amount,
    down_payment_net_amount_paid,
    paid_amount,
    dt_due_invoice_anchor,
    dt_promisse,
    dt_due_promisse,
    dt_cancellation,
    dt_down_payment,
    dt_paid_all_installments,
    dt_expected_ending,
    COALESCE(dt_paid_all_installments, dt_cancellation) AS dt_ending
  FROM calculations
)
SELECT
  sk_negotiation,
  sk_contract,
  sk_debtor,
  sk_operator,
  id_negotiation,
  id_negotiation_trato_feito,
  id_manager_authorized,
  id_campaign,
  creditor,
  source,
  is_not_standard_negotiation,
  not_standard_reason,
  agreement_type,
  agreement_type_description,
  advisory,
  origin_agreement,
  campaign_status,
  broken_reason,
  negotiation_status,
  negotiation_classification,
  promisse_payment_method,
  payment_method,
  is_renegotiation,
  has_been_renegotiated,
  delay_contamined_range,
  total_invoices_negotiated,
  number_of_installments,
  paid_installments,
  breached_installments,
  CAST(original_debt_amount AS DECIMAL(14,2)) AS original_debt_amount,
  CAST(fine_fee_amount AS DECIMAL(14,2)) AS fine_fee_amount,
  CAST(interest_fee_amount AS DECIMAL(14,2)) AS interest_fee_amount,
  CAST(credit_card_fee_amount AS DECIMAL(14,2)) AS credit_card_fee_amount,
  CAST(installment_eviction_costs AS DECIMAL(14,2)) AS installment_eviction_costs,
  CAST(installment_lawyers_fee AS DECIMAL(14,2)) AS installment_lawyers_fee,
  CAST(total_debt_amount AS DECIMAL(14,2)) AS total_debt_amount,
  CAST(total_discount_amount AS DECIMAL(14,2)) AS total_discount_amount,
  CAST(discount_to_fees_amount AS DECIMAL(14,2)) AS discount_to_fees_amount,
  CAST(discount_to_credit_fee_amount AS DECIMAL(14,2)) AS discount_to_credit_fee_amount,
  CAST(discount_to_original_amount AS DECIMAL(14,2)) AS discount_to_original_amount,
  CAST(negotiated_amount AS DECIMAL(14,2)) AS negotiated_amount,
  CAST(down_payment_original_amount AS DECIMAL(14,2)) AS down_payment_original_amount,
  CAST(down_payment_amount AS DECIMAL(14,2)) AS down_payment_amount,
  CAST(CASE
    WHEN number_of_installments = 1
        THEN original_debt_amount - discount_to_original_amount
    ELSE down_payment_net_amount
  END AS DECIMAL(14,2)) AS down_payment_net_amount,
  CAST(CASE
    WHEN number_of_installments = 1
      AND dt_down_payment IS NOT NULL
        THEN original_debt_amount - discount_to_original_amount
    ELSE down_payment_net_amount_paid
  END AS DECIMAL(14,2)) AS down_payment_net_amount_paid,
  CAST(CASE
    WHEN (promisse_payment_method = "CARTÃO DE CRÉDITO" OR number_of_installments = 1)
      AND dt_down_payment IS NOT NULL
        THEN original_debt_amount - discount_to_original_amount
    WHEN promisse_payment_method != "CARTÃO DE CRÉDITO"
      AND number_of_installments != 1
      AND down_payment_net_amount_paid != 0
        THEN down_payment_net_amount_paid
    ELSE 0
  END AS DECIMAL(14,2)) AS net_paid_amount,
  CAST(paid_amount AS DECIMAL(14,2)) AS paid_amount,
  dt_due_invoice_anchor,
  dt_promisse,
  dt_due_promisse,
  dt_cancellation,
  dt_down_payment,
  dt_paid_all_installments,
  dt_expected_ending,
  dt_ending,
  NOW() AS ts_load
FROM calculate_discounts
