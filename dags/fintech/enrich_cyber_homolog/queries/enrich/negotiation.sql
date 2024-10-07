WITH
amount_details AS (
  SELECT
    ad.id_agreement,
    SUM(IF(ad.field_name IN ("Juros Residuais", "Juros Acordo"), ad.amount_without_discount, 0)) AS contract_interest_fees_amount,
    SUM(IF(ad.field_name IN ("Multa Residual", "Multa Acordo"), ad.amount_without_discount, 0)) AS fine_amount,
    SUM(IF(ad.field_name IN ("Parcelas Vencidas", "Parcelas a Vencer"), ad.amount_without_discount, 0)) AS original_amount,
    SUM(IF(ad.field_name IN ("Custas Residuais", "Custas Acordo"), ad.amount_without_discount, 0)) AS eviction_costs_amount,
    SUM(IF(ad.field_name IN ("Parcelas Vencidas", "Parcelas a Vencer"), ad.discount, 0)) AS discount_to_original_amount,
    SUM(IF(ad.field_name IN ("Juros Residuais", "Juros Acordo"), ad.discount, 0)) AS discount_to_fees_amount,
    SUM(IF(ad.field_name IN ("Multa Residual", "Multa Acordo"), ad.discount, 0)) AS discount_to_fine_amount,
    SUM(IF(ad.field_name IN ("Custas Residuais", "Custas Acordo"), ad.discount, 0)) AS discount_to_eviction_costs,
    SUM(ad.amount_without_discount) AS debt_amount,
    SUM(ad.amount_with_discount) AS negotiated_amount,
    SUM(ad.discount) AS discount_amount
  FROM datalake_cyber_clean.agreement_discounts AS ad
  GROUP BY 1
),
installments AS (
  SELECT
    ai.id_agreement,
    MIN(IF(ai.status = 'Quebrado', DATE(ai.ts_due_installment), NULL)) AS dt_cancelation,
    MAX(IF(ai.installment_number = 0, p.payment_method, NULL)) AS promisse_payment_method,
    COUNT(DISTINCT ai.id_agreement_installment) AS number_of_installments,
    MAX(IF(p.id_agreement_installment IS NOT NULL, ai.installment_number + 1, 0)) AS paid_installments,
    SUM(ai.amount_to_pay) AS negotiated_amount,
    SUM(ai.credit_card_fee_amount) AS credit_card_fee_amount,
    SUM(ai.installment_interest_amount) AS installment_interest_fees_amount,
    SUM(IF(p.id_agreement_installment IS NOT NULL AND ai.installment_number = 0, p.payment_amount, 0)) AS down_payment_amount,
    CASE
      WHEN COUNT(DISTINCT p.id_payment) = COUNT(DISTINCT ai.id_agreement_installment) THEN MAX(DATE(p.ts_payment))
    END AS dt_paid_all,
    MIN(IF(ai.installment_number = 0, DATE(ai.ts_due_installment), NULL)) AS dt_due_promisse,
    MAX(IF(p.id_agreement_installment IS NOT NULL AND ai.installment_number = 0, DATE(p.ts_payment), NULL)) AS dt_down_payment,
    MAX(DATE(ai.ts_due_installment)) AS dt_expected_end
  FROM datalake_cyber_clean.agreement_installments AS ai
  LEFT JOIN datalake_cyber_clean.payments AS p
    ON ai.id_agreement_installment = p.id_agreement_installment
  GROUP BY 1
),
discount_type AS (
  SELECT
    id_agreement_type,
    MAX(max_discount_level_1) FILTER (WHERE label = 'Juros Acordo') AS max_interest_discount_percentage,
    MAX(max_discount_level_1) FILTER (WHERE label = 'Multa Acordo') AS max_fine_discount_percentage,
    MAX(max_discount_level_1) FILTER (WHERE label = 'Parcelas Vencidas') AS max_main_amount_discount_percantage
  FROM datalake_cyber_clean.agreement_type_discount
  WHERE LOWER(field_name) IN ('u1vlrprcag','u1vlrmuag','u1vlrjuag')
  GROUP BY 1
),
total_invoices_negotiated AS (
  SELECT
    id_negotiation,
    COUNT(DISTINCT id_invoice) AS total_invoices_negotiated
  FROM datalake_cyber_homolog.debt_negotiation_mapping
  GROUP BY 1
),
deduplicate_agency_group AS (
  SELECT
    agency_group,
    id_agency
  FROM datalake_cyber_clean.agency_group
  QUALIFY ROW_NUMBER() OVER(PARTITION BY agency_group ORDER BY percentage_remuneration DESC) = 1
),
get_agency_group_name AS (
  SELECT
    ag.agency_group,
    a.id_agency,
    a.agency_name
  FROM deduplicate_agency_group AS ag
  LEFT JOIN datalake_cyber_clean.agency AS a
    ON ag.id_agency = a.id_agency
)
SELECT
    a.id_agreement AS id_negotiation,
    ca.id_contract,
    c.id_contract_external,
    c.id_client AS id_customer,
    UPPER(a.id_user) AS id_operator,
    CASE
      WHEN COALESCE(agg.agency_name, ag.agency_name) LIKE "PASCH%" THEN "PASCHOALOTTO"
      WHEN UPPER(a.id_user) LIKE "PSC%" THEN "PASCHOALOTTO"
      WHEN UPPER(a.id_user) = "MIGRACAO" THEN "MIGRACAO"
      ELSE UPPER(COALESCE(agg.agency_name, ag.agency_name))
    END AS advisory,
    cp.offer_number AS id_campaign,
    ca.contract_group AS creditor,
    a.frequency,
    a.agreement_type AS agreement_type,
    at.agreement_type_description,
    at.min_delay_days AS agreement_type_min_delay_days,
    at.max_delay_days AS agreement_type_max_delay_days,
    at.payment_method AS agreement_type_payment_method,
    i.promisse_payment_method,
    a.exception,
    at.min_down_payment_percentage,
    CASE
      WHEN ag.agency_type IN ("Assessoria Convencional", "Assessoria Digital") THEN "Assessoria"
      WHEN ag.agency_type = "Portal" THEN "Portal Auto Negociação"
      WHEN ag.agency_type = "Cyber Credit" THEN "Operador Interno"
      WHEN cp.id_campaign IS NOT NULL OR UPPER(a.agreement_type) LIKE '%CAM%' THEN "Carta Campanha"
      WHEN UPPER(a.id_user) = "MIGRACAO" THEN "Migração"
      ELSE ag.agency_type
    END AS origin_agreement,
    a.status AS original_negotiation_status,
    CASE
        WHEN a.status = "Cancelado" AND i.dt_down_payment IS NOT NULL THEN "broken"
        WHEN a.status = "Cancelado" AND i.dt_down_payment IS NULL THEN "canceled"
        WHEN a.status = "Finalizado" THEN "finished"
        WHEN a.status = "Autorizado" AND i.dt_down_payment IS NOT NULL THEN "offset"
        WHEN a.status = "Autorizado" AND i.dt_down_payment IS NULL THEN "started"
        WHEN a.status = "Pendente" THEN "pending"
        ELSE a.status
    END AS negotiation_status,
    a.description_broken_agreement,
    IF(i.dt_down_payment IS NOT NULL, TRUE, FALSE) AS is_down_payment_paid,
    tin.total_invoices_negotiated,
    i.number_of_installments,
    i.paid_installments,
    IF(a.status = "Cancelado", i.number_of_installments - i.paid_installments, 0) AS breached_installments,
    d.original_amount,
    a.type_interest_quota,
    a.interest_rate,
    a.additional_interest_rate,
    d.fine_amount,
    d.contract_interest_fees_amount,
    i.installment_interest_fees_amount,
    d.contract_interest_fees_amount + i.installment_interest_fees_amount AS total_interest_fees_amount,
    d.eviction_costs_amount,
    a.honorarium_amount,
    i.credit_card_fee_amount,
    d.debt_amount,
    d.discount_amount,
    d.negotiated_amount + i.credit_card_fee_amount AS negotiated_amount,
    i.down_payment_amount,
    ROUND(a.percentage_paid_agreement, 2) AS percentage_paid_agreement,
    atd.max_interest_discount_percentage,
    atd.max_fine_discount_percentage,
    atd.max_main_amount_discount_percantage,
    d.discount_to_original_amount,
    d.discount_to_fine_amount,
    d.discount_to_fees_amount,
    d.discount_to_eviction_costs,
    a.ts_agreement_creation AS dt_promisse,
    i.dt_due_promisse,
    i.dt_down_payment,
    i.dt_paid_all,
    i.dt_expected_end,
    COALESCE(DATE(a.ts_agreement_breach), a.ts_canceled, i.dt_cancelation) AS dt_cancellation,
    NOW() AS ts_load
FROM datalake_cyber_clean.agreements AS a
INNER JOIN datalake_cyber_clean.contracts_agreements AS ca
  ON a.id_agreement = ca.id_agreement
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON ca.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON UPPER(a.id_user) = UPPER(u.id_user)
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
LEFT JOIN get_agency_group_name AS agg
  ON ag.id_agency = agg.agency_group
LEFT JOIN datalake_cyber_clean.agreement_type AS at
  ON a.agreement_type = at.id_agreement_type
LEFT JOIN discount_type AS atd
  ON a.agreement_type = atd.id_agreement_type
LEFT JOIN amount_details AS d
  ON a.id_agreement = d.id_agreement
LEFT JOIN installments AS i
  ON i.id_agreement = a.id_agreement
LEFT JOIN total_invoices_negotiated AS tin
  ON a.id_agreement = tin.id_negotiation
LEFT JOIN datalake_cyber_clean.campaign AS cp
  ON a.id_agreement = cp.id_agreement
