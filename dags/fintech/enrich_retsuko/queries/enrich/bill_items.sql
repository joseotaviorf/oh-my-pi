WITH cte_split_bill_item AS (
    SELECT
    e.id,
    e.id_invoice,
    UPPER(REVERSE(SPLIT(e.bill_item, '/'))[0]) AS bill_item
    FROM
    datalake_retsuko.entry AS e
)

SELECT
    rcc.id_external AS id_contract,
    rci.id_external AS id_invoice,
    rci.purpose,
    rci.status AS payment_status,
    bi.bill_item AS bill_item,
    rce.description AS bill_item_description,
    CASE
      WHEN bi.bill_item IN ('CONDOMINIUM-DEFAULTING','CONDOMINIUM-5A-PAID', 'CONDOMINIUM-USAGE') THEN 'CONDOMINIO'
      WHEN bi.bill_item = 'EARLY-TERMINATION-FEE' THEN 'MULTA-RECISORIA'
      WHEN bi.bill_item = 'DEBIT-NEGOTIATION' THEN 'ACORDO'
      WHEN bi.bill_item IN ('RENTAL','IPTU','HOME-INSURANCE','SERVICE-FEE','CONDOMINIUM') THEN 'RENTAL-CORE'
      WHEN bi.bill_item IN ('RESIDENTIAL-PROTECTION-5A-ACQUITTANCE','RESIDENTIAL-PROTECTION-5A-FUND-TRANSFER') THEN 'REPAROS'
      WHEN bi.bill_item IN ('FINE-AND-INTEREST','PROPERTY-DAMAGE-FINE') THEN 'MULTAS ONGOING'
      WHEN bi.bill_item IN ('LIGHT-WATER-OR-GAS','UTILITIES-DEFAULTING') THEN 'UTILIDADES'
      ELSE 'OUTROS'
    END AS bill_item_cluster_name,
    rca.type AS from_account_type,
    rcab.type AS to_account_type,
    rce.amount AS value_sign_bill_item,
    rci.due_amount,
    rce.accrual_year_month AS accrual_year_month,
    rci.accrual_year_month AS accrual_year_month_invoice,
    CAST(rci.ts_created AS DATE) AS dt_created,
    CAST(rci.ts_sent AS DATE) AS dt_sent,
    CAST(rci.ts_due AS DATE) AS dt_due,
    CAST(rci.ts_paid AS DATE) AS dt_paid,
    CAST(rci.ts_canceled AS DATE) AS dt_canceled
FROM
    datalake_retsuko.invoice AS rci
    LEFT JOIN cte_split_bill_item AS bi
      ON bi.id_invoice = rci.id
    LEFT JOIN datalake_retsuko.entry AS rce
      ON bi.id = rce.id
    LEFT JOIN datalake_retsuko_clean.account AS rca
      ON rca.id = rce.id_from_account
    LEFT JOIN datalake_retsuko_clean.account AS rcab
      ON rcab.id = rce.id_to_account
    LEFT JOIN datalake_retsuko_clean.contract AS rcc
      ON rcc.id = rci.id_contract
WHERE
    DATE(rci.ts_created) >= DATE_TRUNC('YEAR', CURRENT_DATE - INTERVAL '3 YEARS')
    OR DATE(rci.ts_due) >= DATE_TRUNC('YEAR', CURRENT_DATE - INTERVAL '3 YEARS')
