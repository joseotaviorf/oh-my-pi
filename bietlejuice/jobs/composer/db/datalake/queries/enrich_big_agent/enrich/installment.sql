WITH installment AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.installment
)

SELECT
    id,
    id_external_invoice,
    uuid_installment,
    type,
    amount,
    accrual_year_month,
    status,
    dt_sent_to_bank,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    installment
WHERE
    row_n = 1