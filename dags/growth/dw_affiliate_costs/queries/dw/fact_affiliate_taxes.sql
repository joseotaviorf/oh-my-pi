SELECT
    CAST(id AS BIGINT) AS sk_tax,
    CAST(id_payee AS BIGINT) AS sk_payee,
    CAST(due_amount AS DECIMAL(20, 2)) AS due_amount,
    CAST(accounting_year_month AS BIGINT) AS dt_accounting_year_month,
    NOW() AS ts_load
FROM
    datalake_robin_hood_clean.tax
WHERE
    due_amount IS NOT NULL
