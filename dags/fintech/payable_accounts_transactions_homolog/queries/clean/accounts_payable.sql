SELECT
    `_doc_nf` AS nf_file_description,
    CASE
        WHEN RLIKE(TRIM(REGEXP_REPLACE(fornecedor,'\\p{{Z}}', '' )),"^[0-9]+\\.0+$") THEN REGEXP_REPLACE(TRIM(REGEXP_REPLACE(fornecedor,'\\p{{Z}}', '' )), "\\.0+$", "")
        ELSE TRIM(REGEXP_REPLACE(fornecedor,'\\p{{Z}}', ' ' ))
    END AS supplier_description,
    NULLIF(TRIM(REGEXP_REPLACE(cost_and_profit_center,'\\p{{Z}}', ' ' )), '') AS payment_source,
    NULLIF(TRIM(REGEXP_REPLACE(revenue_and_cost_elements,'\\p{{Z}}', ' ' )), '') AS payment_reason,
    REGEXP_REPLACE(banco,'\\p{{Z}}', '' ) AS bank_description,
    REGEXP_REPLACE(conta,'\\p{{Z}}', '' ) AS account_number,
    CAST(REPLACE(REGEXP_REPLACE(valor_bruto,'\\p{{Z}}', '' ), ',', '') AS NUMERIC(38, 2)) AS paid_amount,
    DATE_FORMAT(TO_DATE(competencia, 'yyyy-MM-dd HH:mm:ss'), 'yyyyMM') AS accrual_year_month,
    TO_DATE(pagamento, 'yyyy-MM-dd HH:mm:ss') AS dt_paid,
    ts_load
FROM
    datalake_payable_accounts_transactions_homolog_raw.accounts_payable
