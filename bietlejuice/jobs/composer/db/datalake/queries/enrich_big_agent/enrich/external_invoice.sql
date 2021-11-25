WITH external_invoice AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_big_agent_clean.external_invoice
)
SELECT
    id,
    id_earning,
    id_external,
    accrual_year_month,
    due_date,
    entries,
    purpose,
    ts_created_external,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    external_invoice
WHERE
    row_n = 1