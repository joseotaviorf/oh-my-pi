WITH
ssn_original_payment AS (
    SELECT DISTINCT
        id_contract,
        id_invoice
    FROM datalake_collections_quintoandar.delinquency_app_events
    WHERE
      funnel_step IN ('Overdue Self Service Action', 'Overdue Self Service Viewed')
      AND id_contract IS NOT NULL
      AND id_invoice IS NOT NULL
),
negotiation_data AS (
  SELECT DISTINCT
    d.id_invoice,
    d.id_contract,
    n.sk_negotiation,
    CAST(n.net_paid_amount / n.original_debt_amount AS DECIMAL(14,2))  AS net_rate,
    IF(n.origin_agreement = "Portal Auto Negociação", TRUE, FALSE) AS is_ssn_boletao
  FROM dw_collection_recovery_quintoandar.fact_debt AS d
  INNER JOIN dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
    ON d.sk_debt = b.sk_debt
  INNER JOIN dw_collection_recovery_quintoandar.fact_negotiation AS n
    ON b.sk_negotiation = n.sk_negotiation
  WHERE
    n.down_payment_net_amount_paid != 0
  QUALIFY ROW_NUMBER() OVER(PARTITION BY d.id_invoice, d.id_contract ORDER BY ABS(DATE_DIFF(n.dt_down_payment, d.dt_paid))) = 1
),
negotiation_installment AS (
  SELECT
    id_invoice_extra AS id_invoice,
    sk_contract AS id_contract,
    sk_negotiation AS sk_origin_negotiation,
    installment_number
  FROM dw_collection_recovery_quintoandar.fact_negotiation_installment
  WHERE id_invoice_extra IS NOT NULL
),
add_all_dimensions AS (
SELECT
    CONCAT(o.id_invoice, o.id_contract, DATE_FORMAT(o.dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    o.id_contract,
    o.id_invoice,
    o.id_proposal,
    o.id_region,
    IF(o.payment_status = "written-down", n.sk_negotiation, NULL) AS sk_negotiation,
    IF(o.invoice_type = "extra", ni.sk_origin_negotiation, NULL) AS sk_origin_negotiation,
    IF(o.invoice_type = "extra", ni.installment_number, NULL) AS negotiation_installment_number,
    o.contract_status,
    o.invoice_type,
    o.payment_status,
    o.reason,
    o.paid_via,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement") AND o.payment_status = "paid" THEN TRUE
        WHEN n.is_ssn_boletao IS NOT NULL AND n.is_ssn_boletao IS TRUE AND o.payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement") AND o.payment_status = "paid" THEN "POSSN (payment of original)"
        WHEN n.is_ssn_boletao IS NOT NULL AND n.is_ssn_boletao IS TRUE AND o.payment_status = "written-down" THEN "BOSSN (single debt negotiation)"
        ELSE NULL
    END AS type_ssn,
    CASE
      WHEN possn.id_invoice IS NOT NULL
        AND o.payment_status = "paid"
        AND o.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement")
      THEN "Self Service Negotiation - Payment of original debt"
      WHEN
        n.is_ssn_boletao IS NOT NULL
        AND n.is_ssn_boletao IS TRUE
        AND o.payment_status = "written-down"
      THEN "Self Service Negotiation - Negotiation"
      WHEN possn.id_invoice IS NULL
        AND (n.is_ssn_boletao IS NULL OR n.is_ssn_boletao IS FALSE)
        AND o.payment_status = 'paid'
        AND o.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement")
        AND o.invoice_type != "extra"
      THEN "Original debt"
      WHEN possn.id_invoice IS NULL
        AND (n.is_ssn_boletao IS NULL OR n.is_ssn_boletao IS FALSE)
        AND o.payment_status = 'written-down'
        AND o.reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement")
        AND o.invoice_type != "extra"
      THEN "Negotiation"
      WHEN possn.id_invoice IS NULL
        AND (n.is_ssn_boletao IS NULL OR n.is_ssn_boletao IS FALSE)
        AND o.payment_status = 'paid'
        AND o.reason IN ("negotiation-recupera", "negotiation-cyber", "agreement")
        AND o.invoice_type = "extra"
      THEN "Negotiation installments (extra)"
    END AS recovery_method,
    o.debtor_type,
    o.delay_contamined_at_closure,
    o.delay_contamined_range,
    o.delay_contract_range,
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
    COALESCE(cad.advisory, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) AS advisory,
    q.segmentation_queue,
    q.segmentation_queue_description,
    q.agreement_queue,
    q.agreement_queue_description,
    q.eviction_queue ,
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
    datalake_invoice.overdue_portfolio_timeline AS o
LEFT JOIN
    ssn_original_payment AS possn
      ON possn.id_invoice = o.id_invoice
      AND possn.id_contract = o.id_contract
LEFT JOIN
    datalake_recupera.contract_advisory_distribution AS rc
      ON o.id_contract = rc.id_contract
      AND o.dt_reference = rc.dt_snapshot
LEFT JOIN
    datalake_cyber.contract_agency_distribution AS cad
      ON o.id_contract = cad.id_contract
      AND o.dt_reference BETWEEN cad.dt_start_interval AND cad.dt_end_interval
LEFT JOIN
    negotiation_data AS n
      ON o.id_invoice = n.id_invoice
      AND o.id_contract = n.id_contract
LEFT JOIN
    negotiation_installment AS ni
      ON o.id_invoice = ni.id_invoice
      AND o.id_contract = ni.id_contract
LEFT JOIN
    datalake_cyber.queue_timeline AS q
      ON o.id_contract = q.id_contract_external
      AND o.dt_reference = q.dt_reference
),
get_last_valid_partner AS (
  -- Get the last valid partner per invoice, to freeze the partner after the invoice payment date
  SELECT
    id_contract,
    id_invoice,
    advisory,
    segmentation_queue,
    segmentation_queue_description,
    agreement_queue,
    agreement_queue_description,
    eviction_queue,
    eviction_queue_description
  FROM add_all_dimensions
  WHERE dt_reference BETWEEN DATE_ADD(max_dt_invoice_paid,-1) AND max_dt_invoice_paid
  AND (advisory IS NULL OR advisory NOT IN ("DBAIXAS", "DCARGA")) -- ignore DBAIXAS, because it references to the paid invoices, and we want the last valid partner before the invoice payment.
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_invoice ORDER BY dt_reference DESC) = 1
)
SELECT
    a.sk_overdue_portfolio_timeline,
    a.id_region AS sk_region,
    a.id_contract AS sk_contract,
    a.sk_negotiation,
    a.sk_origin_negotiation,
    a.id_invoice,
    a.id_proposal,
    a.negotiation_installment_number,
    a.contract_status,
    a.invoice_type,
    a.payment_status,
    a.reason,
    a.paid_via,
    a.is_ssn,
    a.type_ssn,
    a.recovery_method,
    a.debtor_type,
    a.delay_contamined_at_closure,
    a.delay_contamined_range,
    a.delay_contract_range,
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
    a.ts_load
FROM add_all_dimensions AS a
LEFT JOIN get_last_valid_partner AS g
  ON a.id_contract = g.id_contract
    AND a.id_invoice = g.id_invoice
LEFT JOIN datalake_cyber.queue_timeline AS q
  ON a.id_contract = q.id_contract_external
    AND a.dt_reference = q.dt_reference
WHERE
  sk_origin_negotiation IS NULL
  OR (sk_origin_negotiation IS NOT NULL
    AND negotiation_installment_number <> 1)
