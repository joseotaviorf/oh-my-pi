SELECT
    rcc.id_external AS id_contract,
    rci.id_external AS id_invoice,
    rci.purpose AS frequency,
    rci.status AS payment_status,
    REVERSE(SPLIT(rce.bill_item, '/')) [0] AS bill_item,
    rce.description AS bill_item_description,
    rca.type AS from_account_type,
    rcab.type AS to_account_type,
    CASE
      WHEN (
        rca.type = 'contract'
        AND rcab.type <> 'contract') THEN (-1.0) * rce.amount
      ELSE 1.0 * rce.amount
    END AS value_sign_bill_item,
    rce.amount,
    rci.due_amount,
    rce.accrual_year_month AS accrual_year_month,
    rci.accrual_year_month AS accrual_year_month_invoice,
    CAST(rci.ts_created AS DATE) AS dt_created,
    CAST(rci.ts_sent AS DATE) AS dt_sent,
    CAST(rci.ts_due AS DATE) AS dt_due,
    CAST(rci.ts_paid AS DATE) AS dt_paid,
    CAST(rci.ts_canceled AS DATE) AS dt_canceled
FROM
    datalake_retsuko_clean.entry AS rce
    LEFT JOIN datalake_retsuko_clean.invoice AS rci
      ON rce.id_invoice = rci.id
    LEFT JOIN datalake_retsuko_clean.account AS rca
      ON rca.id = rce.id_from_account
    LEFT JOIN datalake_retsuko_clean.account AS rcab
      ON rcab.id = rce.id_to_account
    LEFT JOIN datalake_retsuko_clean.contract AS rcc
      ON rcc.id = rci.id_contract
WHERE
    CAST(rci.ts_created AS DATE) >= DATE('2020-01-01')
