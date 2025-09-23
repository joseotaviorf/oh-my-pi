WITH
negotiation_data AS (
SELECT DISTINCT
    ip.id_invoice,
    ip.id_contract,
    n.sk_negotiation,
    CAST(n.net_paid_amount / n.original_debt_amount AS DECIMAL(14,2))  AS net_rate,
    IF(n.origin_agreement = "Portal Auto Negociação", TRUE, FALSE) AS is_ssn_boletao
  FROM datalake_collections_quintoandar.invoice_portfolio AS ip
  LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation AS n
    ON ip.id_negotiation_child = n.id_negotiation
  WHERE
    n.down_payment_net_amount_paid != 0
  QUALIFY ROW_NUMBER() OVER(PARTITION BY ip.id_invoice, ip.id_contract ORDER BY ABS(DATE_DIFF(n.dt_down_payment, ip.ts_paid))) = 1
),
add_all_dimensions AS (
SELECT
    CONCAT(o.id_invoice, o.id_contract, DATE_FORMAT(o.dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    o.id_contract,
    o.id_invoice,
    o.id_proposal,
    o.id_region,
    cad.id_agency,
    IF(o.payment_status = "written-down", n.sk_negotiation, NULL) AS sk_negotiation,
    IF(o.invoice_type = "extra", CONCAT(COALESCE(o.id_contract, 0), CAST(o.id_negotiation_parent AS STRING)), NULL) AS sk_origin_negotiation,
    IF(o.invoice_type = "extra", o.negotiation_installment_number, NULL) AS negotiation_installment_number,
    o.contract_status,
    o.invoice_type,
    o.payment_status,
    o.reason,
    o.paid_via,
    o.recovery_channel,
    o.debtor_type,
    o.delay_contamined_at_closure,
    o.delay_contamined_range,
    o.delay_contract_range,
    o.delay_invoice_at_reference,
    o.delay_first_payment_default,
    o.contract_overdue_invoices,
    ABS(o.due_amount) AS due_amount,
    o.paid_amount,
    ABS(o.recovered_amount) AS recovered_amount,
    ROUND(CASE
      WHEN o.payment_status = "paid" THEN ABS(o.recovered_amount)
      WHEN o.payment_status = "written-down" AND n.sk_negotiation IS NULL THEN ABS(o.recovered_amount)
      WHEN o.payment_status = "written-down" THEN n.net_rate * ABS(o.recovered_amount)
      ELSE 0
    END, 2) AS net_recovered_amount,
    o.contract_debt,
    o.business_day,
    o.is_last_business_days,
    o.is_write_off,
    o.is_contract_write_off,
    o.is_first_payment_default,
    o.has_app_action_event,
    o.has_matthew_interaction,
    n.is_ssn_boletao,
    COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) AS advisory,
    q.segmentation_queue,
    q.segmentation_queue_description,
    q.agreement_queue,
    q.agreement_queue_description,
    q.eviction_queue,
    q.eviction_queue_description,
    MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice) AS max_dt_invoice_paid, -- get the dt_paid of invoice, since dt_invoice_paid is only filled in when dt_reference >= dt_paid
    o.dt_invoice_paid,
    o.dt_invoice_due,
    o.dt_invoice_due_adjust,
    o.dt_write_off,
    o.dt_month_start,
    o.dt_month_end,
    o.dt_reference,
    NOW() AS ts_load
FROM
    datalake_collections_quintoandar.overdue_portfolio_timeline AS o
LEFT JOIN
    datalake_recupera.contract_advisory_distribution AS rc
      ON o.id_contract = rc.id_contract
      AND o.dt_reference = rc.dt_snapshot
LEFT JOIN
    datalake_collections_quintoandar.agency_timeline AS cad
      ON o.id_contract = cad.id_contract
      AND o.dt_reference = cad.dt_reference
LEFT JOIN
    datalake_cyber.queue_timeline AS q
      ON o.id_contract = q.id_contract_external
      AND o.dt_reference = q.dt_reference
LEFT JOIN
    negotiation_data AS n
      ON o.id_invoice = n.id_invoice
      AND o.id_contract = n.id_contract
),
get_last_valid_partner AS (
  -- Get the last valid partner per invoice, to freeze the partner after the invoice payment date
  SELECT
    id_contract,
    id_invoice,
    id_agency,
    advisory,
    segmentation_queue,
    segmentation_queue_description,
    agreement_queue,
    agreement_queue_description,
    eviction_queue,
    eviction_queue_description
  FROM add_all_dimensions
  WHERE dt_reference >= DATE_ADD(max_dt_invoice_paid,-1) AND dt_reference <= max_dt_invoice_paid
  AND (advisory IS NULL OR advisory NOT IN ("DBAIXAS", "DCARGA")) -- ignore DBAIXAS, because it references to the paid invoices, and we want the last valid partner before the invoice payment.
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_invoice ORDER BY dt_reference DESC) = 1
)
SELECT
    a.sk_overdue_portfolio_timeline,
    a.id_region AS sk_region,
    a.id_contract AS sk_contract,
    a.sk_negotiation,
    a.sk_origin_negotiation,
    IF(a.dt_reference >= a.dt_invoice_paid, g.id_agency, a.id_agency) AS sk_agency,
    a.id_invoice,
    a.id_proposal,
    a.negotiation_installment_number,
    a.contract_status,
    a.invoice_type,
    a.payment_status,
    a.reason,
    a.paid_via,
    CASE
        WHEN a.has_app_action_event IS NOT NULL AND a.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement") AND a.payment_status = "paid" THEN TRUE
        WHEN a.is_ssn_boletao IS NOT NULL AND a.is_ssn_boletao IS TRUE AND a.payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    IF(a.dt_reference >= a.dt_invoice_paid, a.recovery_channel, NULL) AS recovery_channel,
    a.debtor_type,
    a.delay_contamined_at_closure,
    a.delay_contamined_range,
    a.delay_contract_range,
    a.delay_invoice_at_reference,
    a.delay_first_payment_default,
    a.contract_overdue_invoices,
    a.due_amount,
    a.paid_amount,
    a.recovered_amount,
    a.net_recovered_amount,
    a.contract_debt,
    a.business_day,
    a.is_last_business_days,
    a.is_write_off,
    a.is_contract_write_off,
    a.is_first_payment_default,
    a.has_app_action_event,
    a.has_matthew_interaction,
    IF(a.dt_reference >= a.dt_invoice_paid, g.advisory, a.advisory) AS advisory,
    IF(a.dt_reference >= a.dt_invoice_paid, g.segmentation_queue, a.segmentation_queue) AS segmentation_queue,
    IF(a.dt_reference >= a.dt_invoice_paid, g.segmentation_queue_description, a.segmentation_queue_description) AS segmentation_queue_description,
    IF(a.dt_reference >= a.dt_invoice_paid, g.agreement_queue, a.agreement_queue) AS agreement_queue,
    IF(a.dt_reference >= a.dt_invoice_paid, g.agreement_queue_description, a.agreement_queue_description) AS agreement_queue_description,
    IF(a.dt_reference >= a.dt_invoice_paid, g.eviction_queue, a.eviction_queue) AS eviction_queue,
    IF(a.dt_reference >= a.dt_invoice_paid, g.eviction_queue_description, a.eviction_queue_description) AS eviction_queue_description,
    IF(ROW_NUMBER() OVER(PARTITION BY a.id_contract, a.id_invoice, a.dt_month_start ORDER BY a.dt_reference DESC) = 1, TRUE, FALSE) AS is_most_recent_record_month,
    a.dt_invoice_paid,
    a.dt_invoice_due,
    a.dt_invoice_due_adjust,
    a.dt_write_off,
    a.dt_month_start,
    a.dt_month_end,
    a.dt_reference,
    YEAR(a.dt_reference) AS year,
    MONTH(a.dt_reference) AS month,
    DAY(a.dt_reference) AS day,
    a.ts_load
FROM add_all_dimensions AS a
LEFT JOIN get_last_valid_partner AS g
  ON a.id_contract = g.id_contract
    AND a.id_invoice = g.id_invoice
LEFT JOIN datalake_cyber.queue_timeline AS q
  ON a.id_contract = q.id_contract_external
    AND a.dt_reference = q.dt_reference
    AND q.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
WHERE
  a.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND (
    sk_origin_negotiation IS NULL
    OR (sk_origin_negotiation IS NOT NULL
      AND negotiation_installment_number <> 1)
  )
