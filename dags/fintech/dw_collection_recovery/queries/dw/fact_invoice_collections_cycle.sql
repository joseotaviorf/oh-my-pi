WITH
base AS (
  SELECT
    d.id_contract,
    d.id_invoice,
    ni.id_invoice_extra,
    COALESCE(n.id_negotiation_trato_feito, n.sk_negotiation) AS id_negotiation,
    d.dt_invoice_due,
    n.negotiation_status,
    n.negotiated_amount,
    n.dt_promisse,
    n.dt_expected_ending,
    n.number_of_installments,
    n.paid_installments,
    n.dt_paid_all_installments
  FROM dw_collection_recovery.fact_debt AS d
  LEFT JOIN dw_collection_recovery.bridge_map_debt_negotiation AS b
    ON  d.sk_debt = b.sk_debt
  LEFT JOIN dw_collection_recovery.fact_negotiation AS n
    ON b.sk_negotiation = n.sk_negotiation
  LEFT JOIN dw_collection_recovery.fact_negotiation_installment AS ni
    ON ni.sk_negotiation = n.sk_negotiation
  WHERE d.creditor = "IQ QuintoAndar"
),
tracking_invoice AS (
  SELECT
    id_contract,
    MIN(id_invoice) AS id_invoice,
    MAX(IF(negotiation_status = "finished", dt_paid_all_installments, NULL)) AS dt_debt_paid
  FROM base
  GROUP BY 1
),
negotiation_info AS (
  -- Get data on the most recent negotiation (i.e, the one that has not been cancelled) for each invoice.
  SELECT
    id_invoice,
    dt_invoice_due,
    MAX(CASE WHEN negotiation_status != "canceled" THEN dt_paid_all_installments END) AS dt_paid_all_installments,
    MAX(CASE WHEN negotiation_status != "canceled" THEN id_negotiation END) AS id_negotiation,
    MAX(CASE WHEN negotiation_status != "canceled" THEN negotiation_status END) AS negotiation_status,
    COUNT(DISTINCT id_negotiation) AS total_negotiations,
    MAX(CASE WHEN negotiation_status != "canceled" THEN negotiated_amount END) AS negotiation_amount,
    MAX(CASE WHEN negotiation_status != "canceled" THEN dt_promisse END) AS dt_negotiation_created,
    MAX(CASE WHEN negotiation_status != "canceled" THEN dt_expected_ending END) AS dt_expect_finish_negotiation,
    MAX(CASE WHEN negotiation_status != "canceled" THEN number_of_installments END) AS total_negotiation_installments,
    MAX(CASE WHEN negotiation_status != "canceled" THEN paid_installments END) AS total_paid_negotiation_installments
  FROM base
  GROUP BY 1,2
),
negotiation_invoice_extra AS (
  SELECT DISTINCT
    id_invoice_extra,
    id_negotiation
  FROM base
  where id_invoice_extra IS NOT NULL
)
SELECT
  i.id_external AS sk_collections_cycle,
  i.id_contract_external AS id_contract,
  c.id_customer,
  i.id_external AS id_invoice,
  ni.id_negotiation AS id_negotiation_originated_invoice,
  n.id_negotiation,
  IF(ni.id_negotiation IS NOT NULL AND n.id_negotiation IS NOT NULL, TRUE, FALSE) has_renegotiated,
  i.status AS invoice_status,
  i.purpose AS invoice_type,
  n.negotiation_status,
  INT(n.total_negotiations) AS total_negotiations,
  INT(n.total_negotiation_installments) AS total_negotiation_installments,
  INT(n.total_paid_negotiation_installments) AS total_paid_negotiation_installments,
  n.negotiation_amount,
  ABS(i.due_amount) As invoice_due_amount,
  ABS(i.paid_amount) As paid_amount,
  i.accrual_year_month,
  DATE(i.ts_created) AS dt_invoice_created,
  DATE(i.ts_due) AS dt_invoice_due,
  i.dt_due_adjusted AS dt_debt_creation,
  DATE(i.ts_paid) AS dt_paid,
  IF(status = "written-down", DATE(i.ts_paid), NULL) AS dt_written_down,
  it.dt_debt_paid AS dt_original_debt_paid,
  n.dt_negotiation_created,
  n.dt_expect_finish_negotiation,
  NOW() ts_load
FROM datalake_retsuko.invoice AS i
LEFT JOIN dw_public.dim_date AS dd
  ON DATE(i.ts_due) = dd.date
LEFT JOIN negotiation_info AS n
  ON i.id_external = n.id_invoice
LEFT JOIN datalake_recupera_clean.contracts AS c
  ON i.id_contract_external = c.id_contract
LEFT JOIN negotiation_invoice_extra AS ni
  ON i.id_external = ni.id_invoice_extra
LEFT JOIN tracking_invoice AS it
  ON i.id_external = it.id_invoice
WHERE c.id_creditor = 1
