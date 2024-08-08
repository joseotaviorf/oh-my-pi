WITH cte_most_recent AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_pixar_clean.charge
    GROUP BY 1
)
SELECT
    c.id,
    c.id_account,
    c.id_external,
    c.id_transaction,
    c.id_bank_payment,
    c.pix_link,
    c.pix_emv,
    c.amount,
    c.bank_fee,
    c.status,
    c.dt_limit,
    c.ts_created,
    c.ts_updated
FROM
    datalake_pixar_clean.charge c
RIGHT JOIN
    cte_most_recent cte
        ON cte.id = c.id
        AND cte.ts_updated = c.ts_updated
