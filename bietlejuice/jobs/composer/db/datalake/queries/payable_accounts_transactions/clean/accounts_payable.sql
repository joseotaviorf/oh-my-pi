SELECT
    `_doc_nf` AS nf_file_description,
    TRIM(fornecedor) AS supplier_description,
    NULLIF(TRIM(cost_and_profit_center), '') AS payment_source,
    NULLIF(TRIM(revenue_and_cost_elements), '') AS payment_reason,
    banco AS bank_description,
    CAST(REPLACE(valor_bruto, ',', '') AS NUMERIC(38, 2)) AS paid_amount,
    CAST(REPLACE(saldo_total, ',', '') AS NUMERIC(38, 2)) AS account_balance,
    DATE_FORMAT(TO_DATE(competencia, 'yyyy-MM-dd HH:mm:ss'), 'yyyyMM') AS accrual_year_month,
    TO_DATE(pagamento, 'yyyy-MM-dd HH:mm:ss') AS dt_paid,
    ts_load
FROM
    datalake_payable_accounts_transactions_raw.accounts_payable;
