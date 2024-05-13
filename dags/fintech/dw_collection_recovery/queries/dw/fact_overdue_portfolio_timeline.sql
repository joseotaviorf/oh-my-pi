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
        WHEN COALESCE(ors.advisory,ors.distributor) IN ("DVAT130","DVAT3160","DVCOBINT", "DVESPBX") THEN "INTERNO VELO"
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
ssn_boletao AS (
    SELECT DISTINCT
        d.id_external AS id_invoice,
        n.id_contract
    FROM
        datalake_trato_feito_clean.debt AS d
    LEFT JOIN
        datalake_debt_recovery.negotiation AS n
            ON d.id_negotiation = n.id_negotiation
    WHERE n.collector = "5A-collector"
),
add_all_dimensions AS (
SELECT
    CONCAT(o.id_invoice, "-", DATE_FORMAT(o.dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    o.id_contract,
    o.id_invoice,
    o.id_proposal,
    o.contract_status,
    o.invoice_type,
    o.payment_status,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "agreement") AND o.payment_status = "paid" THEN TRUE
        WHEN bossn.id_invoice IS NOT NULL AND o.payment_status = "written-down" THEN TRUE
        ELSE FALSE
    END AS is_ssn,
    CASE
        WHEN possn.id_invoice IS NOT NULL AND o.reason NOT IN ("negotiation-recupera", "agreement") AND o.payment_status = "paid" THEN "POSSN (payment of original)"
        WHEN bossn.id_invoice IS NOT NULL AND o.payment_status = "written-down" THEN "BOSSN (single debt negotiation)"
        ELSE NULL
    END AS type_ssn,
    o.debtor_type,
    o.delay_contamined_range,
    o.contract_overdue_invoices,
    o.due_amount,
    o.paid_amount,
    o.recovered_amount,
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
LEFT JOIN ssn_boletao AS bossn
    ON bossn.id_invoice = o.id_invoice
    AND bossn.id_contract = o.id_contract
LEFT JOIN responsible_for_contract AS rc
  ON o.id_contract = rc.id_contract
  AND o.dt_reference = rc.dt_snapshot
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
    a.id_contract,
    a.id_invoice,
    a.id_proposal,
    a.contract_status,
    a.invoice_type,
    a.payment_status,
    a.is_ssn,
    a.type_ssn,
    a.debtor_type,
    a.delay_contamined_range,
    a.contract_overdue_invoices,
    a.due_amount,
    a.paid_amount,
    a.recovered_amount,
    a.contract_debt,
    a.business_day,
    a.is_last_business_days,
    IF(a.dt_reference >= a.dt_invoice_paid, g.advisory, a.advisory) AS advisory,
    IF(a.dt_reference >= a.dt_invoice_paid, g.distributor, a.distributor) AS distributor,
    IF(a.dt_reference >= a.dt_invoice_paid, g.partner, a.partner) AS partner,
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
