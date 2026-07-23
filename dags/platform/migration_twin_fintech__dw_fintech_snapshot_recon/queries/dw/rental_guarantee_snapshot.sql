SELECT
    g.id,
    g.id_contract_ebdb,
    g.guarantee_type,
    gc.payment_recurrence,
    g.guarantee_status,
    g.ts_started,
    g.ts_cancellation_requested,
    g.ts_paid,
    g.ts_expired,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    datalake_rental_guarantee.guarantee AS g
LEFT JOIN
    datalake_rental_guarantee_clean.guarantee AS gc
        ON g.id = gc.id
