SELECT
    c.sk_contract AS id_contract_ebdb,
    di.payment_status AS invoice_payment_status,
    c.tenant_service_fee,
    ROUND((c.rent * c.tenant_service_fee),2) AS prod_theorical_amount,
    ROUND(SUM(fie.brl_entry_due_amount),2) AS invoice_theorical_amount,
    ROUND(SUM(fie.brl_entry_paid_amount),2) AS invoice_paid_amount,
    CASE WHEN c.guarantee = 'SeguroFairfax' AND
          (die.producer != 'onboarding-routine' AND
          die.producer != 'onboarding-routine-delayed') THEN INT(DATE_FORMAT(ADD_MONTHS(TO_DATE(STRING(i.accrual_year_month), "yyyyMM"),1), "yyyyMM"))
          ELSE CAST(i.accrual_year_month AS string) END AS accrual_year_month,
    DATE(di.ts_due) AS dt_due,
    DATE(di.ts_paid) AS dt_paid
FROM
    datalake_invoice.invoice_entries fie
INNER JOIN datalake_retsuko.invoice_entry die
    ON fie.id = die.id
LEFT JOIN datalake_retsuko.invoice_info di
    ON di.id_invoice = fie.id_invoice
LEFT JOIN datalake_retsuko.invoice i
    ON di.id_invoice = i.id_external
LEFT JOIN dw_rent.dim_contract c
    ON c.sk_contract = fie.id_contract
WHERE
    die.from_account_type NOT IN ('quinto andar', 'contract expenses')
AND
    di.payment_status <> 'canceled'
AND
    die.entry_type = 'service fee'
GROUP BY 1,2,3,4,7,8,9
