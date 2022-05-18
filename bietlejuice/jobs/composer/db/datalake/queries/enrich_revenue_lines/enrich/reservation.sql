SELECT
    r.id_reservation,
    r.status,
    r.cancellation_reason,
    r.installments AS total_installments,
    CAST(r.value/r.installments AS DECIMAL(19,2)) AS monthly_value,
    CAST(r.value AS DECIMAL(19,2)) AS total_value,
    DATE_FORMAT(dd.month_start,'yyyyMM') AS accrual_month,
    CASE
        WHEN r.installments <= 1 
            THEN DATE(r.ts_created)
        ELSE ADD_MONTHS(DATE(r.ts_created), (r.installments - 1)) 
    END AS dt_end_payment,
    DATE(r.ts_created) AS dt_created
FROM
    datalake_kill_queue.reservation AS r
INNER JOIN 
    datalake_quintoandar.aux_date AS dd
        ON dd.month_start BETWEEN DATE_TRUNC('month', DATE(r.ts_created)) 
          AND DATE_TRUNC('month', (CASE
                WHEN r.installments <= 1 
                    THEN DATE(r.ts_created)
                ELSE ADD_MONTHS(DATE(r.ts_created), (r.installments - 1)) 
               END))
WHERE
    r.id_reservation > 0
    AND r.is_ongoing IS NULL
    AND (r.status IN ('FINISHED', 'CHARGED') OR (r.status = 'CANCELED' AND (r.cancellation_reason = 'TENANT_GAVE_UP' OR r.cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
