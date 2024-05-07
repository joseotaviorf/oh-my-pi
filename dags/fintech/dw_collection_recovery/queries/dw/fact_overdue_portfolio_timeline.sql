WITH
distinct_contract_customer AS (
  SELECT DISTINCT
    id_contract,
    id_customer
  FROM datalake_recupera_clean.contracts
),
contract_per_day AS (
  SELECT DISTINCT
    c.id_contract,
    c.id_customer,
    d.date
  FROM datalake_quintoandar.aux_date AS d
  CROSS JOIN distinct_contract_customer AS c
  WHERE d.date BETWEEN DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH)
    AND CURRENT_DATE - INTERVAL "1" DAY
),
operational_records AS (
  SELECT DISTINCT
    id_customer,
    advisory_code AS advisory,
    distributor_code AS distributor,
    MAKE_DATE(year, month, day) AS dt_snapshot
  FROM datalake_recupera_clean.operational_records
  WHERE id_creditor = '1' -- filter quintoandar
    AND MAKE_DATE(year, month, day) BETWEEN DATE_TRUNC("month", CURRENT_DATE - INTERVAL "48" MONTH) AND CURRENT_DATE - INTERVAL "1" DAY
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_customer, MAKE_DATE(year, month, day) ORDER BY ts_last_update DESC) = 1
),
partner_per_day_and_contract AS (
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
    c.date AS dt_snapshot
  FROM contract_per_day AS c
  LEFT JOIN operational_records As ors
    ON ors.id_customer = c.id_customer
    AND ors.dt_snapshot = c.date
),
responsible_for_contract AS (
    SELECT DISTINCT
        id_contract,
        COALESCE(advisory, LAG(advisory) IGNORE NULLS OVER(PARTITION BY id_contract ORDER BY dt_snapshot)) AS advisory,
        COALESCE(distributor, LAG(distributor) IGNORE NULLS OVER(PARTITION BY id_contract ORDER BY dt_snapshot)) AS distributor,
        COALESCE(partner, LAG(partner) IGNORE NULLS OVER(PARTITION BY id_contract ORDER BY dt_snapshot)) AS partner,
        dt_snapshot
    FROM partner_per_day_and_contract
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, dt_snapshot ORDER BY partner DESC) = 1
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
)
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
    rc.partner,
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
