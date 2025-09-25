WITH
negotiation_data AS (
  SELECT DISTINCT
    ip.id_invoice,
    ip.id_contract,
    n.sk_negotiation,
    CAST(n.net_paid_amount / n.original_debt_amount AS DECIMAL(14,2)) AS net_rate,
    IF(n.origin_agreement = "Portal Auto Negociação", TRUE, FALSE) AS is_ssn_boletao
  FROM datalake_collections_quintoandar.invoice_portfolio AS ip
  LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation AS n
    ON ip.id_negotiation_child = n.id_negotiation
  WHERE
    n.down_payment_net_amount_paid != 0
  QUALIFY ROW_NUMBER() OVER(PARTITION BY ip.id_invoice, ip.id_contract ORDER BY ABS(DATE_DIFF(n.dt_down_payment, ip.ts_paid))) = 1
),
base_data AS (
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
    MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice) AS max_dt_invoice_paid,
    o.dt_invoice_paid,
    o.dt_invoice_due,
    o.dt_invoice_due_adjust,
    o.dt_write_off,
    o.dt_month_start,
    o.dt_month_end,
    o.dt_reference,
    NOW() AS ts_load,
    -- Pre-calculate the last valid partner data using window functions
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN cad.id_agency
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_id_agency,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference))
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_advisory,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.segmentation_queue
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_segmentation_queue,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.segmentation_queue_description
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_segmentation_queue_description,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.agreement_queue
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_agreement_queue,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.agreement_queue_description
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_agreement_queue_description,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.eviction_queue
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_eviction_queue,
    LAST_VALUE(CASE
      WHEN o.dt_reference >= DATE_ADD(MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice), -1)
           AND o.dt_reference <= MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice)
           AND (COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) IS NULL
                OR COALESCE(cad.main_agency_name, rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) NOT IN ("DBAIXAS", "DCARGA"))
      THEN q.eviction_queue_description
    END) IGNORE NULLS OVER(PARTITION BY o.id_contract, o.id_invoice ORDER BY o.dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_valid_eviction_queue_description
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
)
SELECT
    sk_overdue_portfolio_timeline,
    id_region AS sk_region,
    id_contract AS sk_contract,
    sk_negotiation,
    sk_origin_negotiation,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_id_agency
        ELSE id_agency
    END AS sk_agency,
    id_invoice,
    id_proposal,
    negotiation_installment_number,
    contract_status,
    invoice_type,
    payment_status,
    reason,
    paid_via,
    CASE
        WHEN has_app_action_event IS NOT NULL AND reason NOT IN ("negotiation-recupera", "negotiation-cyber", "agreement") AND payment_status = "paid" THEN TRUE
        WHEN is_ssn_boletao IS NOT NULL AND is_ssn_boletao IS TRUE AND payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN recovery_channel
        ELSE NULL
    END AS recovery_channel,
    debtor_type,
    delay_contamined_at_closure,
    delay_contamined_range,
    delay_contract_range,
    delay_invoice_at_reference,
    delay_first_payment_default,
    contract_overdue_invoices,
    due_amount,
    paid_amount,
    recovered_amount,
    net_recovered_amount,
    contract_debt,
    business_day,
    is_last_business_days,
    is_write_off,
    is_contract_write_off,
    is_first_payment_default,
    has_app_action_event,
    has_matthew_interaction,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_advisory
        ELSE advisory
    END AS advisory,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_segmentation_queue
        ELSE segmentation_queue
    END AS segmentation_queue,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_segmentation_queue_description
        ELSE segmentation_queue_description
    END AS segmentation_queue_description,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_agreement_queue
        ELSE agreement_queue
    END AS agreement_queue,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_agreement_queue_description
        ELSE agreement_queue_description
    END AS agreement_queue_description,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_eviction_queue
        ELSE eviction_queue
    END AS eviction_queue,
    CASE
        WHEN dt_reference >= dt_invoice_paid THEN last_valid_eviction_queue_description
        ELSE eviction_queue_description
    END AS eviction_queue_description,
    IF(ROW_NUMBER() OVER(PARTITION BY id_contract, id_invoice, dt_month_start ORDER BY dt_reference DESC) = 1, TRUE, FALSE) AS is_most_recent_record_month,
    dt_invoice_paid,
    dt_invoice_due,
    dt_invoice_due_adjust,
    dt_write_off,
    dt_month_start,
    dt_month_end,
    dt_reference,
    YEAR(dt_reference) AS year,
    MONTH(dt_reference) AS month,
    DAY(dt_reference) AS day,
    ts_load
FROM base_data
WHERE
  (sk_origin_negotiation IS NULL
  OR (sk_origin_negotiation IS NOT NULL AND negotiation_installment_number <> 1))
  AND dt_reference >= DATE('{load_start_date}') - 30 AND dt_reference <= DATE('{load_end_date}')
