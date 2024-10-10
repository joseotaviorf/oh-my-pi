WITH
distinct_contract_customer AS (
  SELECT DISTINCT
    id_contract,
    id_customer
  FROM datalake_recupera_clean.contracts
),
operational_records AS (
  SELECT DISTINCT
    id_customer,
    advisory_code AS advisory,
    distributor_code AS distributor,
    ts_customer_status_last_update,
    MAKE_DATE(year, month, day) AS dt_snapshot
  FROM datalake_recupera_clean.operational_records
  WHERE id_creditor = '1' -- filter quintoandar
    AND MAKE_DATE(year, month, day) BETWEEN DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH) AND CURRENT_DATE - INTERVAL "1" DAY
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer, MAKE_DATE(year, month, day) ORDER BY ts_last_update DESC) = 1
),
responsible_for_contract AS (
  SELECT DISTINCT
    c.id_contract,
    ors.advisory,
    ors.distributor,
    CASE
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("DACORDEV","DEVICEX","DEVICTIO", "DEVICFIN") THEN "EVICTIONS"
        WHEN COALESCE(ors.advisory,ors.distributor) = "DASSES" THEN "EXTERNO"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("DAT130","DAT3160","DAT61","DONBOARD","DACOINTE","DBOLPULA","DPREEVIC", "DACOVNQB") THEN "INTERNO"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("DLEGAL","DPCOB","DPCOBFR") THEN "INTERNO BLOQUEADO"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("V5PASCHW", "QPASCHWS","VPASCHWS") THEN "PASCHOALOTTO"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("VIAFWS","V5IAFWS", 'QIAFWS') THEN "IAF"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("DESPBXQT","DACOBLGQ","DCBINTQT") THEN "QUITEI BLOQUEADO"
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("QWHELPWS","WEBHELP") THEN "WEBHELP"
        ELSE COALESCE(ors.advisory,ors.distributor)
    END AS partner,
    ors.dt_snapshot
  FROM operational_records As ors
  LEFT JOIN distinct_contract_customer AS c
    ON ors.id_customer = c.id_customer
  QUALIFY ROW_NUMBER() OVER(PARTITION BY c.id_contract, ors.dt_snapshot ORDER BY ors.ts_customer_status_last_update DESC) = 1

),
ssn_original_payment AS (
    -- Service Self Negotiation where customer paid the original invoice
    SELECT DISTINCT
        event_properties:contract_id AS id_contract,
        event_properties:invoice_id AS id_invoice
    FROM
        datalake_amplitude_clean.170698_pending_invoices_invoice_pay_button_clicked_events
    WHERE
        event_properties:contract_id IS NOT NULL
        AND event_properties:invoice_id IS NOT NULL
),
negotiation_data AS (
  SELECT DISTINCT
    d.id_invoice,
    d.id_contract,
    CASE
      WHEN LOWER(n.promisse_payment_method) LIKE '%cartão%' THEN n.original_debt_amount
      ELSE n.down_payment_amount_paid
    END AS net_recovery_amount,
    IF(n.origin_agreement = "Portal Auto Negociação", TRUE, FALSE) AS is_ssn_boletao
  FROM dw_collection_recovery_quintoandar.fact_debt AS d
  INNER JOIN dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
    ON d.sk_debt = b.sk_debt
  INNER JOIN dw_collection_recovery_quintoandar.fact_negotiation AS n
    ON b.sk_negotiation = n.sk_negotiation
  WHERE
    n.down_payment_amount_paid != 0
    AND n.negotiation_status IN ("broken", "finished", "offset")
  QUALIFY ROW_NUMBER() OVER(PARTITION BY d.id_invoice, d.id_contract ORDER BY ABS(DATE_DIFF(n.dt_down_payment, d.dt_paid))) = 1
),
add_all_dimensions AS (
SELECT
    CONCAT(o.id_invoice, "-", DATE_FORMAT(o.dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    o.id_contract,
    o.id_invoice,
    o.id_proposal,
    o.id_region,
    o.contract_status,
    o.invoice_type,
    o.payment_status,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "agreement") AND o.payment_status = "paid" THEN TRUE
        WHEN n.is_ssn_boletao IS NOT NULL AND o.payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "agreement") AND o.payment_status = "paid" THEN "POSSN (payment of original)"
        WHEN n.is_ssn_boletao IS NOT NULL AND o.payment_status = "written-down" THEN "BOSSN (single debt negotiation)"
        ELSE NULL
    END AS type_ssn,
    CASE
      WHEN possn.id_invoice IS NOT NULL
        AND o.payment_status = "paid"
        AND o.reason NOT IN ("negotiation-recupera", "agreement")
      THEN "Self Service Negotiation - Payment of original debt"
      WHEN n.id_invoice IS NOT NULL
        AND o.payment_status = "written-down"
      THEN "Self Service Negotiation - Negotiation"
      WHEN possn.id_invoice IS NULL
        AND n.id_invoice IS NULL
        AND o.payment_status = 'paid'
        AND o.reason NOT IN ("negotiation-recupera", "agreement")
        AND o.invoice_type != "extra"
      THEN "Original debt"
      WHEN possn.id_invoice IS NULL
        AND n.id_invoice IS NULL
        AND o.payment_status = 'written-down'
        AND o.reason NOT IN ("negotiation-recupera", "agreement")
        AND o.invoice_type != "extra"
      THEN "Negotiation"
      WHEN possn.id_invoice IS NULL
        AND n.id_invoice IS NULL
        AND o.payment_status = 'paid'
        AND o.reason IN ("negotiation-recupera", "agreement")
        AND o.invoice_type = "extra"
      THEN "Negotiation installments (extra)"
    END AS recovery_method,
    o.debtor_type,
    o.delay_contamined_at_closure,
    o.delay_contamined_range,
    o.delay_contract_range,
    o.contract_overdue_invoices,
    o.due_amount,
    o.paid_amount,
    o.recovered_amount,
    CASE
        WHEN o.dt_invoice_paid BETWEEN o.dt_month_start AND o.dt_reference
            AND o.dt_invoice_paid > o.dt_invoice_due_adjust
        THEN n.net_recovery_amount
        ELSE 0
    END AS net_recovery_amount,
    o.contract_debt,
    o.business_day,
    o.is_last_business_days,
    rc.advisory,
    rc.distributor,
    COALESCE(rc.partner, LAG(rc.partner) IGNORE NULLS OVER(PARTITION BY o.id_contract ORDER BY o.dt_reference)) AS partner,
    MAX(o.dt_invoice_paid) OVER(PARTITION BY o.id_contract, o.id_invoice) AS max_dt_invoice_paid, -- get the dt_paid of invoice, since dt_invoice_paid is only filled in when dt_reference >= dt_paid
    o.dt_invoice_paid,
    o.dt_invoice_due,
    o.dt_invoice_due_adjust,
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
LEFT JOIN responsible_for_contract AS rc
  ON o.id_contract = rc.id_contract
  AND o.dt_reference = rc.dt_snapshot
LEFT JOIN negotiation_data AS n
  ON o.id_invoice = n.id_invoice
    AND o.id_contract = n.id_contract
),
get_last_valid_partner AS (
  -- Get the last valid partner per invoice, to freeze the partner after the invoice payment date
  SELECT
    id_contract,
    id_invoice,
    advisory,
    distributor,
    partner
  FROM add_all_dimensions
  WHERE dt_reference BETWEEN DATE_ADD(max_dt_invoice_paid,-1) AND max_dt_invoice_paid
  AND partner IS NULL OR partner NOT IN ("DBAIXAS", "DCARGA") -- ignore DBAIXAS, because it references to the paid invoices, and we want the last valid partner before the invoice payment.
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, id_invoice ORDER BY dt_reference DESC) = 1
)
SELECT
    a.sk_overdue_portfolio_timeline,
    a.id_region AS sk_region,
    a.id_contract AS sk_contract,
    a.id_invoice,
    a.id_proposal,
    a.contract_status,
    a.invoice_type,
    a.payment_status,
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
    a.net_recovery_amount,
    a.contract_debt,
    a.business_day,
    a.is_last_business_days,
    IF(a.dt_reference >= a.dt_invoice_paid, g.advisory, a.advisory) AS advisory,
    IF(a.dt_reference >= a.dt_invoice_paid, g.distributor, a.distributor) AS distributor,
    IF(a.dt_reference >= a.dt_invoice_paid, g.partner, a.partner) AS partner,
    IF(ROW_NUMBER() OVER(PARTITION BY a.id_contract, a.id_invoice, a.dt_month_start ORDER BY a.dt_reference DESC) = 1, TRUE, FALSE) AS is_most_recent_record_month,
    a.dt_invoice_paid,
    a.dt_invoice_due,
    a.dt_invoice_due_adjust,
    a.dt_month_start,
    a.dt_month_end,
    a.dt_reference,
    a.ts_load
FROM add_all_dimensions AS a
LEFT JOIN get_last_valid_partner AS g
  ON a.id_contract = g.id_contract
    AND a.id_invoice = g.id_invoice
