WITH
amount_details AS (
  SELECT
    COALESCE(ad.id_agreement, cd.id_offer) AS id_agreement,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Juros Residuais", "Juros Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS contract_interest_fees_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Multa Residuais", "Multa Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS fine_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Parcelas Vencidas", "Parcelas a Vencer"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS original_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Custas Residuais", "Custas Acordo"), COALESCE(ad.amount_without_discount, cd.amount_without_discount), 0)) AS eviction_costs_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Parcelas Vencidas", "Parcelas a Vencer"), COALESCE(ad.discount, cd.discount), 0)) AS discount_to_original_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Juros Residuais", "Juros Acordo"), COALESCE(ad.discount, cd.discount), 0)) AS discount_to_fees_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Multa Residuais", "Multa Acordo"), COALESCE(ad.discount, cd.discount), 0)) AS discount_to_fine_amount,
    SUM(IF(COALESCE(ad.field_name, cd.field_name) IN ("Custas Residuais", "Custas Acordo"), COALESCE(ad.discount, cd.discount), 0)) AS discount_to_eviction_costs,
    SUM(COALESCE(ad.amount_without_discount, cd.amount_without_discount)) AS debt_amount,
    SUM(COALESCE(ad.amount_with_discount, cd.amount_with_discount)) AS negotiated_amount,
    SUM(COALESCE(ad.discount, cd.discount)) AS discount_amount
  FROM datalake_cyber_clean.agreement_discounts AS ad
  FULL OUTER JOIN datalake_cyber_clean.campaign_discounts AS cd
    ON ad.id_agreement = cd.id_offer
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
    SUM(IF(p.id_agreement_installment IS NOT NULL AND ai.installment_number = 0, ai.amount_to_pay, 0)) AS down_payment_amount,
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
campaign_installments AS (
  SELECT
    id_offer,
    SUM(installment_interest_amount) AS installment_interest_fees_amount
  FROM datalake_cyber_clean.campaign_installments
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
  FROM datalake_cyber.debt_negotiation_mapping
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
),
deduplicate_agreement_type AS (
  SELECT DISTINCT
    id_agreement_type,
    agreement_type_description,
    min_delay_days,
    max_delay_days,
    payment_method,
    min_down_payment_percentage
  FROM datalake_cyber_clean.agreement_type
),
union_promisses_agreements AS (
  SELECT
    COALESCE(a.id_agreement, c.id_agreement) AS id_agreement,
    COALESCE(ca.id_contract, c.id_contract) AS id_contract,
    COALESCE(a.id_client, c.id_client) AS id_client,
    c.id_campaign,
    c.campaign_status,
    UPPER(a.id_user) AS id_user,
    c.id_agency,
    COALESCE(ca.creditor, a.creditor, c.creditor) AS creditor,
    COALESCE(a.frequency, c.frequency) AS frequency,
    COALESCE(a.agreement_type, c.agreement_type) AS agreement_type,
    i.promisse_payment_method,
    a.exception,
    a.status,
    a.description_broken_agreement,
    COALESCE(i.number_of_installments, a.number_of_installments, c.total_installments) AS number_of_installments,
    i.paid_installments,
    d.original_amount,
    COALESCE(a.type_interest_quota, c.type_interest_quota) AS type_interest_quota,
    COALESCE(a.installment_interest_rate, c.installment_interest_rate) AS installment_interest_rate,
    COALESCE(a.additional_interest_rate, c.grace_period_interest_rate) AS additional_interest_rate,
    d.fine_amount,
    d.contract_interest_fees_amount,
    COALESCE(i.installment_interest_fees_amount, ci.installment_interest_fees_amount) AS installment_interest_fees_amount,
    i.credit_card_fee_amount,
    d.eviction_costs_amount,
    COALESCE(a.honorarium_amount, c.honorarium_amount) AS honorarium_amount,
    d.debt_amount,
    d.discount_amount,
    COALESCE(d.negotiated_amount, c.total_negotiated_without_honorarium) AS negotiated_amount,
    COALESCE(i.down_payment_amount, c.down_payment_amount) AS down_payment_amount,
    ROUND(a.percentage_paid_agreement, 2) AS percentage_paid_agreement,
    d.discount_to_original_amount,
    d.discount_to_fine_amount,
    d.discount_to_fees_amount,
    d.discount_to_eviction_costs,
    COALESCE(a.ts_agreement_creation, DATE(c.ts_boletagem_sent)) AS dt_promisse,
    COALESCE(i.dt_due_promisse, DATE(c.ts_due_down_payment)) AS dt_due_promisse,
    i.dt_down_payment,
    i.dt_paid_all,
    i.dt_expected_end,
    CASE
      WHEN a.status = "Cancelado" THEN a.ts_status_update
      WHEN c.campaign_status = "Vencida" THEN DATE(c.ts_due_boletagem)
      WHEN a.ts_agreement_breach IS NOT NULL THEN DATE(a.ts_agreement_breach)
      WHEN a.ts_canceled IS NOT NULL THEN DATE(a.ts_canceled)
    END AS dt_cancellation
  FROM datalake_cyber_clean.agreements AS a
  LEFT JOIN datalake_cyber_clean.contracts_agreements AS ca
    ON a.id_agreement = ca.id_agreement
  LEFT JOIN amount_details AS d
    ON a.id_agreement = d.id_agreement
  LEFT JOIN installments AS i
    ON i.id_agreement = a.id_agreement
  FULL OUTER JOIN datalake_cyber_clean.campaign AS c
    ON a.id_agreement = c.id_agreement
  LEFT JOIN campaign_installments AS ci
    ON c.id_offer = ci.id_offer
)
SELECT
    CAST(a.id_agreement AS STRING) AS id_negotiation,
    a.id_contract AS id_contract_cyber,
    c.id_contract_external AS id_contract,
    COALESCE(c.id_client, a.id_client) AS id_customer,
    a.id_user AS id_operator,
    a.id_campaign,
    COALESCE(c.creditor, a.creditor) AS creditor,
    CASE
      WHEN a.id_user = "MIGRACAO" THEN "MIGRACAO"
      WHEN UPPER(COALESCE(agg.agency_name, ag.agency_name)) LIKE "PASCH%" THEN "PASCHOALOTTO"
      WHEN UPPER(a.id_user) LIKE "PSC%" THEN "PASCHOALOTTO"
      WHEN UPPER(a.id_user) LIKE "%SERASA%" THEN "SERASA DIGITAL"
      ELSE UPPER(COALESCE(agg.agency_name, ag.agency_name))
    END AS advisory,
    a.frequency,
    a.agreement_type AS agreement_type,
    at.agreement_type_description,
    at.min_delay_days AS agreement_type_min_delay_days,
    at.max_delay_days AS agreement_type_max_delay_days,
    at.payment_method AS agreement_type_payment_method,
    a.promisse_payment_method,
    a.exception,
    at.min_down_payment_percentage,
    CASE
      WHEN a.id_campaign IS NOT NULL OR UPPER(a.agreement_type) LIKE '%CAM%' THEN "Boletagem"
      WHEN ag.agency_type = "Portal" THEN "Portal Auto Negociação"
      WHEN ag.agency_type = "Cyber Credit" THEN "Operador Interno"
      WHEN a.id_user = "MIGRACAO" THEN "Migração"
      WHEN ag.agency_type = "SE" THEN "Serasa Digital"
      ELSE ag.agency_type
    END AS origin_agreement,
    a.status AS original_negotiation_status,
    CASE
        WHEN a.status = "Cancelado" AND a.dt_down_payment IS NOT NULL THEN "broken"
        WHEN a.status = "Cancelado" AND a.dt_down_payment IS NULL THEN "canceled"
        WHEN a.status = "Finalizado" THEN "finished"
        WHEN a.status = "Autorizado" AND a.dt_down_payment IS NOT NULL THEN "offset"
        WHEN a.status = "Autorizado" AND a.dt_down_payment IS NULL THEN "started"
        WHEN a.status = "Pendente" THEN "pending"
        ELSE a.status
    END AS negotiation_status,
    a.campaign_status,
    a.description_broken_agreement,
    IF(a.dt_down_payment IS NOT NULL, TRUE, FALSE) AS is_down_payment_paid,
    tin.total_invoices_negotiated,
    a.number_of_installments,
    a.paid_installments,
    IF(a.status = "Cancelado", a.number_of_installments - a.paid_installments, 0) AS breached_installments,
    a.original_amount,
    a.type_interest_quota,
    a.installment_interest_rate,
    a.additional_interest_rate,
    a.fine_amount,
    a.contract_interest_fees_amount,
    a.installment_interest_fees_amount,
    a.contract_interest_fees_amount + a.installment_interest_fees_amount AS total_interest_fees_amount,
    a.eviction_costs_amount,
    a.honorarium_amount,
    a.credit_card_fee_amount,
    a.debt_amount,
    a.discount_amount,
    a.negotiated_amount + a.credit_card_fee_amount AS negotiated_amount,
    a.down_payment_amount,
    a.percentage_paid_agreement,
    atd.max_interest_discount_percentage,
    atd.max_fine_discount_percentage,
    atd.max_main_amount_discount_percantage,
    a.discount_to_original_amount,
    a.discount_to_fine_amount,
    a.discount_to_fees_amount,
    a.discount_to_eviction_costs,
    a.dt_promisse,
    a.dt_due_promisse,
    a.dt_down_payment,
    a.dt_paid_all,
    a.dt_expected_end,
    a.dt_cancellation,
    NOW() AS ts_load
FROM union_promisses_agreements AS a
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON a.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.users AS u
  ON a.id_user = UPPER(u.id_user)
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON COALESCE(u.id_agency, a.id_agency) = ag.id_agency
LEFT JOIN get_agency_group_name AS agg
  ON ag.id_agency = agg.agency_group
LEFT JOIN deduplicate_agreement_type AS at
  ON a.agreement_type = at.id_agreement_type
LEFT JOIN discount_type AS atd
  ON a.agreement_type = atd.id_agreement_type
LEFT JOIN total_invoices_negotiated AS tin
  ON a.id_agreement = tin.id_negotiation
